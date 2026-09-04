package com.maomao.proxy.maomao.vpn

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import com.maomao.proxy.maomao.core.CoreBridge
import java.util.Timer
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.concurrent.timerTask

/**
 * Owns the platform TUN interface and drives the embedded core's lifecycle.
 *
 * Routing is configured entirely here: the core runs with auto-route disabled
 * because it has no root privileges on Android.
 */
class MaomaoVpnService : VpnService(), CoreBridge.Listener {

    private var descriptor: ParcelFileDescriptor? = null
    private var notification: VpnNotification? = null
    private var trafficTimer: Timer? = null
    private var profileName: String = "maomao"

    /** Serialises tunnel transitions so a stop can never overtake a pending start. */
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var running = false

    override fun onCreate() {
        super.onCreate()
        notification = VpnNotification(this)
        CoreBridge.init(this)
        CoreBridge.attachService(this)
        CoreBridge.addListener(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopAndFinish()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                val options = intent.toVpnOptions()
                if (options == null) {
                    Log.e(TAG, "start requested without a config path")
                    stopSelf()
                    return START_NOT_STICKY
                }
                // Must happen inside the startForegroundService grace period, so it
                // cannot wait behind the config parse on the worker.
                promoteToForeground()
                worker.execute { startTunnel(options) }
                return START_STICKY
            }
        }
        // Reached when the system restarts a sticky service or on "always-on VPN".
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        stopAndFinish()
    }

    override fun onDestroy() {
        CoreBridge.removeListener(this)
        CoreBridge.detachService(this)
        val teardown = worker.submit { stopTunnel() }
        worker.shutdown()
        runCatching { teardown.get(TEARDOWN_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
            .onFailure { Log.w(TAG, "tunnel teardown did not finish in time", it) }
        super.onDestroy()
    }

    private fun stopAndFinish() {
        worker.execute {
            stopTunnel()
            main.post { stopSelf() }
        }
    }

    private fun startTunnel(options: VpnOptions) {
        if (running) {
            reload(options)
            return
        }

        // Parsing here doubles as validation; the core rejects a bad config before
        // anything is applied.
        val tun = try {
            CoreBridge.tunOptions(options.configPath)
        } catch (e: Exception) {
            broadcastError("invalid config: ${e.message}")
            main.post { stopSelf() }
            return
        }

        val pfd = establishTun(options, tun)
        if (pfd == null) {
            broadcastError("failed to establish VPN interface")
            main.post { stopSelf() }
            return
        }
        descriptor = pfd

        // The core takes ownership of the descriptor via os.NewFile, so it must be
        // detached here; keeping the ParcelFileDescriptor would double-close the fd.
        val fd = pfd.detachFd()
        try {
            CoreBridge.start(options.configPath, fd, options.tunStack, tun.mtu)
        } catch (e: Exception) {
            broadcastError("failed to start core: ${e.message}")
            closeDescriptor()
            main.post { stopSelf() }
            return
        }

        running = true
        startTrafficUpdates()
    }

    private fun reload(options: VpnOptions) {
        try {
            CoreBridge.reload(options.configPath)
        } catch (e: Exception) {
            broadcastError("failed to reload config: ${e.message}")
        }
    }

    private fun establishTun(
        options: VpnOptions,
        tun: CoreBridge.TunOptions,
    ): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession(profileName)
            .setMtu(tun.mtu)
            .setBlocking(false)

        // Must mirror the core's inet4-address, which it narrows to a /30 from
        // fake-ip-range regardless of user configuration.
        val ipv4 = tun.ipv4 ?: DEFAULT_IPV4
        val (ipv4Address, ipv4Prefix) = ipv4.splitPrefix(DEFAULT_IPV4_PREFIX)
        builder.addAddress(ipv4Address, ipv4Prefix)

        if (options.ipv6) {
            tun.ipv6?.let {
                val (address, prefix) = it.splitPrefix(DEFAULT_IPV6_PREFIX)
                builder.addAddress(address, prefix)
            }
        }

        tun.dns?.let { builder.addDnsServer(it) }

        if (options.bypassPrivateRoutes && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Keep LAN traffic off the tunnel while still capturing everything else.
            builder.addRoute(android.net.IpPrefix(java.net.InetAddress.getByName("0.0.0.0"), 0))
            PRIVATE_ROUTES.forEach { (address, prefix) ->
                builder.excludeRoute(
                    android.net.IpPrefix(java.net.InetAddress.getByName(address), prefix),
                )
            }
        } else {
            builder.addRoute("0.0.0.0", 0)
        }

        if (options.ipv6) {
            builder.addRoute("::", 0)
        }

        applyAppFilter(builder, options)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        return try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "establish failed", e)
            null
        }
    }

    private fun applyAppFilter(builder: Builder, options: VpnOptions) {
        if (options.allowedApps.isNotEmpty()) {
            var added = false
            options.allowedApps.forEach { pkg ->
                if (pkg == packageName) return@forEach
                runCatching { builder.addAllowedApplication(pkg) }
                    .onSuccess { added = true }
                    .onFailure { Log.w(TAG, "unknown allowed package: $pkg") }
            }
            // An empty allow-list would tunnel every app, inverting the user's intent.
            if (!added) {
                runCatching { builder.addAllowedApplication(packageName) }
            }
            return
        }

        // Always exclude ourselves so subscription downloads and the RESTful
        // controller do not loop back through the tunnel.
        runCatching { builder.addDisallowedApplication(packageName) }
        options.disallowedApps.forEach { pkg ->
            if (pkg == packageName) return@forEach
            runCatching { builder.addDisallowedApplication(pkg) }
                .onFailure { Log.w(TAG, "unknown disallowed package: $pkg") }
        }
    }

    private fun promoteToForeground() {
        val built = notification?.build(profileName, null) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                VpnNotification.NOTIFICATION_ID,
                built,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(VpnNotification.NOTIFICATION_ID, built)
        }
    }

    private fun startTrafficUpdates() {
        trafficTimer?.cancel()
        trafficTimer = Timer("maomao-traffic", true).also { timer ->
            timer.schedule(
                timerTask {
                    if (!running) return@timerTask
                    val traffic = runCatching { CoreBridge.traffic() }.getOrNull() ?: return@timerTask
                    val text = "↑ ${traffic.up.toRate()}  ↓ ${traffic.down.toRate()}"
                    notification?.let { it.update(it.build(profileName, text)) }
                },
                TRAFFIC_INTERVAL_MS,
                TRAFFIC_INTERVAL_MS,
            )
        }
    }

    private fun stopTunnel() {
        trafficTimer?.cancel()
        trafficTimer = null
        if (running) {
            running = false
            runCatching { CoreBridge.stop() }
        }
        closeDescriptor()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun closeDescriptor() {
        runCatching { descriptor?.close() }
        descriptor = null
    }

    private fun broadcastError(message: String) {
        Log.e(TAG, message)
        CoreBridge.onLog("error", message)
    }

    override fun onState(state: String) = Unit

    override fun onLog(level: String, payload: String) = Unit

    private fun Intent.toVpnOptions(): VpnOptions? {
        val configPath = getStringExtra(EXTRA_CONFIG_PATH) ?: return null
        return VpnOptions(
            configPath = configPath,
            tunStack = getStringExtra(EXTRA_TUN_STACK) ?: VpnOptions.STACK_GVISOR,
            allowedApps = getStringArrayListExtra(EXTRA_ALLOWED_APPS) ?: emptyList(),
            disallowedApps = getStringArrayListExtra(EXTRA_DISALLOWED_APPS) ?: emptyList(),
            ipv6 = getBooleanExtra(EXTRA_IPV6, false),
            bypassPrivateRoutes = getBooleanExtra(EXTRA_BYPASS_PRIVATE, true),
        ).also { profileName = getStringExtra(EXTRA_PROFILE_NAME) ?: "maomao" }
    }

    companion object {
        private const val TAG = "MaomaoVpnService"
        private const val TRAFFIC_INTERVAL_MS = 1000L
        private const val TEARDOWN_TIMEOUT_MS = 3000L

        const val ACTION_START = "com.maomao.proxy.action.START"
        const val ACTION_STOP = "com.maomao.proxy.action.STOP"

        const val EXTRA_CONFIG_PATH = "configPath"
        const val EXTRA_PROFILE_NAME = "profileName"
        const val EXTRA_TUN_STACK = "tunStack"
        const val EXTRA_ALLOWED_APPS = "allowedApps"
        const val EXTRA_DISALLOWED_APPS = "disallowedApps"
        const val EXTRA_IPV6 = "ipv6"
        const val EXTRA_BYPASS_PRIVATE = "bypassPrivateRoutes"

        private const val DEFAULT_IPV4 = "198.18.0.1/30"
        private const val DEFAULT_IPV4_PREFIX = 30
        private const val DEFAULT_IPV6_PREFIX = 126

        private val PRIVATE_ROUTES = listOf(
            "10.0.0.0" to 8,
            "172.16.0.0" to 12,
            "192.168.0.0" to 16,
            "169.254.0.0" to 16,
            "224.0.0.0" to 4,
        )
    }
}

private fun String.splitPrefix(fallback: Int): Pair<String, Int> {
    val index = indexOf('/')
    if (index < 0) return this to fallback
    val prefix = substring(index + 1).toIntOrNull() ?: fallback
    return substring(0, index) to prefix
}

private fun Long.toRate(): String {
    val units = arrayOf("B/s", "KB/s", "MB/s", "GB/s")
    var value = toDouble()
    var unit = 0
    while (value >= 1024 && unit < units.lastIndex) {
        value /= 1024
        unit++
    }
    return if (unit == 0) "${value.toInt()} ${units[unit]}"
    else String.format("%.1f %s", value, units[unit])
}
