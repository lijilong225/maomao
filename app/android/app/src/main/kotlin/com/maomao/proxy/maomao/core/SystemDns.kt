package com.maomao.proxy.maomao.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log

/**
 * Feeds the platform DNS servers to the core.
 *
 * The core is built with the `cmfa` tag, which strips its `/etc/resolv.conf`
 * reader because Android does not expose one. Without this the core falls back
 * to a pair of hard-coded public resolvers, which fail on networks that block
 * them, and every hostname it resolves outside the tunnel breaks — including the
 * geoip/geosite downloads triggered while a config is parsed.
 */
object SystemDns {

    /**
     * Networks are tracked instead of read once because DNS servers change with
     * connectivity, and the core caches the client list until told otherwise.
     * Ordered so the most recently updated network's servers are tried first.
     */
    private val servers = LinkedHashMap<Network, List<String>>()

    @Volatile
    private var started = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) {
            val addresses = properties.dnsServers.mapNotNull { it.hostAddress }
            synchronized(this@SystemDns) {
                servers.remove(network)
                if (addresses.isNotEmpty()) servers[network] = addresses
                publish()
            }
        }

        override fun onLost(network: Network) {
            synchronized(this@SystemDns) {
                servers.remove(network)
                publish()
            }
        }
    }

    @Synchronized
    fun start(context: Context) {
        if (started) return
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return
        // The default request already excludes VPNs, so our own tunnel's resolver
        // cannot be handed back to the core and create a resolution loop.
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        try {
            manager.registerNetworkCallback(request, callback)
        } catch (e: Exception) {
            Log.w(TAG, "cannot observe system DNS", e)
            return
        }
        started = true
        // Callbacks arrive asynchronously, but a config may be parsed the moment
        // the app starts, so seed the list from the current network right away.
        seed(manager)
    }

    private fun seed(manager: ConnectivityManager) {
        val network = manager.activeNetwork ?: return
        val capabilities = manager.getNetworkCapabilities(network) ?: return
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return
        val properties = manager.getLinkProperties(network) ?: return
        val addresses = properties.dnsServers.mapNotNull { it.hostAddress }
        if (addresses.isEmpty()) return
        servers.putIfAbsent(network, addresses)
        publish()
    }

    private fun publish() {
        val flat = servers.values.flatten().distinct()
        runCatching { CoreBridge.setSystemDns(flat.joinToString(",")) }
            .onFailure { Log.w(TAG, "cannot update system DNS", it) }
    }

    private const val TAG = "SystemDns"
}
