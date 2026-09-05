package com.maomao.proxy.maomao.vpn

import android.content.Context
import android.content.Intent
import androidx.core.content.edit

/**
 * Starts and stops [MaomaoVpnService], and remembers the last used options so the
 * Quick Settings tile can restart the tunnel without the UI being alive.
 */
object VpnLauncher {

    private const val PREFS = "maomao_vpn"
    private const val KEY_CONFIG_PATH = "configPath"
    private const val KEY_PROFILE_NAME = "profileName"
    private const val KEY_TUN_STACK = "tunStack"
    private const val KEY_ALLOWED = "allowedApps"
    private const val KEY_DISALLOWED = "disallowedApps"
    private const val KEY_IPV6 = "ipv6"
    private const val KEY_BYPASS_PRIVATE = "bypassPrivateRoutes"
    private const val SEPARATOR = "\n"

    fun start(context: Context, options: VpnOptions, profileName: String = "maomao") {
        remember(context, options, profileName)
        val intent = Intent(context, MaomaoVpnService::class.java).apply {
            action = MaomaoVpnService.ACTION_START
            putExtra(MaomaoVpnService.EXTRA_CONFIG_PATH, options.configPath)
            putExtra(MaomaoVpnService.EXTRA_PROFILE_NAME, profileName)
            putExtra(MaomaoVpnService.EXTRA_ENGINE, options.engine)
            putExtra(MaomaoVpnService.EXTRA_TUN_STACK, options.tunStack)
            putStringArrayListExtra(
                MaomaoVpnService.EXTRA_ALLOWED_APPS,
                ArrayList(options.allowedApps),
            )
            putStringArrayListExtra(
                MaomaoVpnService.EXTRA_DISALLOWED_APPS,
                ArrayList(options.disallowedApps),
            )
            putExtra(MaomaoVpnService.EXTRA_IPV6, options.ipv6)
            putExtra(MaomaoVpnService.EXTRA_BYPASS_PRIVATE, options.bypassPrivateRoutes)
        }
        // A VpnService must be a foreground service, so it is always started this way.
        context.startForegroundService(intent)
    }

    fun stop(context: Context) {
        val intent = Intent(context, MaomaoVpnService::class.java).apply {
            action = MaomaoVpnService.ACTION_STOP
        }
        context.startService(intent)
    }

    private fun remember(context: Context, options: VpnOptions, profileName: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
            putString(KEY_CONFIG_PATH, options.configPath)
            putString(KEY_PROFILE_NAME, profileName)
            putString(KEY_TUN_STACK, options.tunStack)
            putString(KEY_ALLOWED, options.allowedApps.joinToString(SEPARATOR))
            putString(KEY_DISALLOWED, options.disallowedApps.joinToString(SEPARATOR))
            putBoolean(KEY_IPV6, options.ipv6)
            putBoolean(KEY_BYPASS_PRIVATE, options.bypassPrivateRoutes)
        }
    }

    fun lastOptions(context: Context): VpnOptions? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val configPath = prefs.getString(KEY_CONFIG_PATH, null) ?: return null
        return VpnOptions(
            configPath = configPath,
            tunStack = prefs.getString(KEY_TUN_STACK, null) ?: VpnOptions.STACK_GVISOR,
            allowedApps = prefs.getString(KEY_ALLOWED, "").orEmpty().splitList(),
            disallowedApps = prefs.getString(KEY_DISALLOWED, "").orEmpty().splitList(),
            ipv6 = prefs.getBoolean(KEY_IPV6, false),
            bypassPrivateRoutes = prefs.getBoolean(KEY_BYPASS_PRIVATE, true),
        )
    }

    fun lastProfileName(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PROFILE_NAME, null) ?: "maomao"

    private fun String.splitList(): List<String> =
        if (isEmpty()) emptyList() else split(SEPARATOR).filter { it.isNotBlank() }
}
