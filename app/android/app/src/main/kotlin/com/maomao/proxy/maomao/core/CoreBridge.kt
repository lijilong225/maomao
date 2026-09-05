package com.maomao.proxy.maomao.core

import android.content.Context
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import com.maomao.proxy.bridge.Bridge
import com.maomao.proxy.bridge.Delegate
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference

/**
 * Single entry point to the embedded mihomo core.
 *
 * The core is a process-wide singleton, so state lives here rather than on the
 * service instance, which Android may recreate.
 */
object CoreBridge : Delegate {

    /** Receives core events on the main thread. */
    interface Listener {
        fun onState(state: String)
        fun onLog(level: String, payload: String)
    }

    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableListOf<Listener>()

    @Volatile
    private var initialized = false

    /**
     * Weakly held so a destroyed service cannot be resurrected by the core's
     * socket-protect callback.
     */
    @Volatile
    private var serviceRef: WeakReference<VpnService> = WeakReference(null)

    @Volatile
    var lastState: String = Bridge.StateStopped
        private set

    val version: String get() = Bridge.version()

    /** Version compiled in for [engine], whether or not it owns the tunnel. */
    fun versionOf(engine: String): String = Bridge.versionOf(engine)

    /**
     * Prepares the core. The home directory holds its assets: geoip/geosite
     * databases, cache and fake-ip state.
     */
    @Synchronized
    fun init(context: Context) {
        if (initialized) return
        val homeDir = File(context.filesDir, "core")
        homeDir.mkdirs()
        Bridge.init(homeDir.absolutePath)
        Bridge.registerDelegate(this)
        initialized = true
        lastState = Bridge.state()
        SystemDns.start(context.applicationContext)
    }

    /** Comma-separated resolver addresses; see [SystemDns] for why this is needed. */
    fun setSystemDns(servers: String) = Bridge.setSystemDNS(servers)

    fun attachService(service: VpnService) {
        serviceRef = WeakReference(service)
    }

    fun detachService(service: VpnService) {
        if (serviceRef.get() === service) {
            serviceRef = WeakReference(null)
        }
    }

    @Synchronized
    fun addListener(listener: Listener) {
        listeners.add(listener)
    }

    @Synchronized
    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    /** Throws on invalid configuration; the caller should surface the message verbatim. */
    fun validateConfig(engine: String, configPath: String) =
        Bridge.validateConfig(engine, configPath)

    /** Normalizes a raw subscription body (YAML or share links) into mihomo YAML. */
    fun convertSubscription(raw: String): String = Bridge.convertSubscription(raw)

    /** Deep-merges a user override patch onto a base config. */
    fun mergeConfig(baseYaml: String, patchYaml: String): String =
        Bridge.mergeConfig(baseYaml, patchYaml)

    /** Translates a mihomo YAML config into a sing-box JSON config. */
    fun convertToSingbox(yaml: String): String = Bridge.convertToSingbox(yaml)

    /**
     * TUN parameters derived from the config. The core narrows fake-ip-range to a
     * /30 and ignores host overrides, so the VpnService builder must mirror these.
     */
    fun tunOptions(engine: String, configPath: String): TunOptions {
        val json = JSONObject(Bridge.tunOptions(engine, configPath))
        return TunOptions(
            ipv4 = json.optString("ipv4").takeIf { it.isNotEmpty() },
            ipv6 = json.optString("ipv6").takeIf { it.isNotEmpty() },
            mtu = json.optInt("mtu", DEFAULT_MTU),
            dns = json.optString("dns").takeIf { it.isNotEmpty() },
        )
    }

    fun start(engine: String, configPath: String, tunFd: Int, tunStack: String, tunMtu: Int) {
        val options = JSONObject()
            .put("engine", engine)
            .put("configPath", configPath)
            .put("tunFd", tunFd)
            .put("tunStack", tunStack)
            .put("tunMTU", tunMtu)
        Bridge.start(options.toString())
    }

    fun reload(configPath: String) = Bridge.reload(configPath)

    fun stop() = Bridge.stop()

    /** Loopback RESTful controller endpoint and per-run secret. */
    fun controllerInfo(): Pair<String, String> {
        val json = JSONObject(Bridge.controllerInfo())
        return json.optString("addr") to json.optString("secret")
    }

    fun traffic(): Traffic = parseTraffic(Bridge.traffic())

    fun trafficTotal(): Traffic = parseTraffic(Bridge.trafficTotal())

    private fun parseTraffic(raw: String): Traffic {
        val json = JSONObject(raw)
        return Traffic(json.optLong("up"), json.optLong("down"))
    }

    // --- Delegate, invoked from Go threads ---

    override fun protect(fd: Int): Boolean {
        // Without this the core's own sockets would be routed back into the tunnel.
        // No service means no tunnel of ours to escape, and failing here would break
        // every socket the core opens outside a session, e.g. config validation.
        val service = serviceRef.get() ?: return true
        return service.protect(fd)
    }

    override fun onState(state: String) {
        lastState = state
        dispatch { it.onState(state) }
    }

    override fun onLog(level: String, payload: String) {
        dispatch { it.onLog(level, payload) }
    }

    private fun dispatch(block: (Listener) -> Unit) {
        main.post {
            val snapshot = synchronized(this) { listeners.toList() }
            snapshot.forEach(block)
        }
    }

    const val DEFAULT_MTU = 9000

    data class TunOptions(
        val ipv4: String?,
        val ipv6: String?,
        val mtu: Int,
        val dns: String?,
    )

    data class Traffic(val up: Long, val down: Long)
}
