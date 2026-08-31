package com.maomao.proxy.maomao.vpn

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.maomao.proxy.maomao.MainActivity
import com.maomao.proxy.maomao.core.CoreBridge
import com.maomao.proxy.bridge.Bridge

/** Quick Settings tile for toggling the tunnel without opening the app. */
@RequiresApi(Build.VERSION_CODES.N)
class MaomaoTileService : TileService(), CoreBridge.Listener {

    override fun onStartListening() {
        super.onStartListening()
        CoreBridge.addListener(this)
        refresh()
    }

    override fun onStopListening() {
        CoreBridge.removeListener(this)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (CoreBridge.lastState == Bridge.StateStopped) {
            // Starting needs consent and the last-used profile, both of which live in
            // the app, so hand off to the UI instead of guessing here.
            if (VpnService.prepare(this) != null || VpnLauncher.lastOptions(this) == null) {
                launchApp()
                return
            }
            VpnLauncher.start(this, VpnLauncher.lastOptions(this)!!)
        } else {
            VpnLauncher.stop(this)
        }
        refresh()
    }

    override fun onState(state: String) = refresh()

    override fun onLog(level: String, payload: String) = Unit

    private fun refresh() {
        val tile = qsTile ?: return
        val active = CoreBridge.lastState != Bridge.StateStopped
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(com.maomao.proxy.maomao.R.string.tile_label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = CoreBridge.lastState
        }
        tile.updateTile()
    }

    private fun launchApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                android.app.PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
