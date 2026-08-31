package com.maomao.proxy.maomao

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import com.maomao.proxy.maomao.core.CoreBridge
import com.maomao.proxy.maomao.vpn.VpnLauncher
import com.maomao.proxy.maomao.vpn.VpnOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * Bridges the Flutter layer to the embedded core and the VPN service.
 *
 * Only lifecycle and platform-only capabilities go through here; high-frequency
 * read-only data (connections, logs, traffic) is served by the core's loopback
 * RESTful controller, whose address and secret are exposed via `controllerInfo`.
 */
class MaomaoPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    CoreBridge.Listener,
    PluginRegistry.ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var events: EventChannel.EventSink? = null

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPrepare: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        CoreBridge.init(File(binding.applicationContext.filesDir, "core"))

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> result.success(CoreBridge.version)
            "state" -> result.success(CoreBridge.lastState)
            "controllerInfo" -> {
                val (addr, secret) = CoreBridge.controllerInfo()
                result.success(mapOf("addr" to addr, "secret" to secret))
            }

            "prepareVpn" -> prepareVpn(result)

            "validateConfig" -> {
                val path = call.argument<String>("configPath")
                if (path == null) {
                    result.error("invalid_argument", "configPath is required", null)
                    return
                }
                try {
                    CoreBridge.validateConfig(path)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("invalid_config", e.message, null)
                }
            }

            "convertSubscription" -> {
                val raw = call.argument<String>("raw")
                if (raw == null) {
                    result.error("invalid_argument", "raw is required", null)
                    return
                }
                try {
                    result.success(CoreBridge.convertSubscription(raw))
                } catch (e: Exception) {
                    result.error("invalid_subscription", e.message, null)
                }
            }

            "mergeConfig" -> {
                val base = call.argument<String>("base") ?: ""
                val patch = call.argument<String>("patch") ?: ""
                try {
                    result.success(CoreBridge.mergeConfig(base, patch))
                } catch (e: Exception) {
                    result.error("invalid_config", e.message, null)
                }
            }

            "start" -> start(call, result)

            "stop" -> {
                val context = context() ?: return result.error("no_context", "not attached", null)
                VpnLauncher.stop(context)
                result.success(null)
            }

            "traffic" -> {
                val traffic = CoreBridge.traffic()
                result.success(mapOf("up" to traffic.up, "down" to traffic.down))
            }

            "trafficTotal" -> {
                val traffic = CoreBridge.trafficTotal()
                result.success(mapOf("up" to traffic.up, "down" to traffic.down))
            }

            "installedApps" -> result.success(installedApps())

            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val context = context() ?: return result.error("no_context", "not attached", null)
        val configPath = call.argument<String>("configPath")
        if (configPath == null) {
            result.error("invalid_argument", "configPath is required", null)
            return
        }
        if (VpnService.prepare(context) != null) {
            result.error("not_prepared", "VPN permission has not been granted", null)
            return
        }

        val options = VpnOptions(
            configPath = configPath,
            tunStack = call.argument<String>("tunStack") ?: VpnOptions.STACK_GVISOR,
            allowedApps = call.argument<List<String>>("allowedApps") ?: emptyList(),
            disallowedApps = call.argument<List<String>>("disallowedApps") ?: emptyList(),
            ipv6 = call.argument<Boolean>("ipv6") ?: false,
            bypassPrivateRoutes = call.argument<Boolean>("bypassPrivateRoutes") ?: true,
        )
        VpnLauncher.start(context, options, call.argument<String>("profileName") ?: "maomao")
        result.success(null)
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
            ?: return result.error("no_activity", "not attached to an activity", null)
        val intent = VpnService.prepare(activity)
        if (intent == null) {
            result.success(true)
            return
        }
        if (pendingPrepare != null) {
            result.error("in_progress", "a consent dialog is already showing", null)
            return
        }
        pendingPrepare = result
        activity.startActivityForResult(intent, REQUEST_PREPARE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PREPARE) return false
        pendingPrepare?.success(resultCode == Activity.RESULT_OK)
        pendingPrepare = null
        return true
    }

    private fun installedApps(): List<Map<String, Any?>> {
        val context = context() ?: return emptyList()
        val pm = context.packageManager
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(
                PackageManager.ApplicationInfoFlags.of(0L),
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(0)
        }
        return packages.map { info ->
            mapOf(
                "packageName" to info.packageName,
                "label" to pm.getApplicationLabel(info).toString(),
                "system" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
            )
        }
    }

    private fun context() = activityBinding?.activity?.applicationContext

    // --- EventChannel ---

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        CoreBridge.addListener(this)
        sink?.success(mapOf("type" to "state", "state" to CoreBridge.lastState))
    }

    override fun onCancel(arguments: Any?) {
        CoreBridge.removeListener(this)
        events = null
    }

    override fun onState(state: String) {
        events?.success(mapOf("type" to "state", "state" to state))
    }

    override fun onLog(level: String, payload: String) {
        events?.success(mapOf("type" to "log", "level" to level, "payload" to payload))
    }

    companion object {
        private const val METHOD_CHANNEL = "com.maomao.proxy/core"
        private const val EVENT_CHANNEL = "com.maomao.proxy/core_events"
        private const val REQUEST_PREPARE = 0x6d61
    }
}
