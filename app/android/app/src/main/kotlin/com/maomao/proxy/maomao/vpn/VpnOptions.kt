package com.maomao.proxy.maomao.vpn

/** Parameters handed to [MaomaoVpnService] when starting the tunnel. */
data class VpnOptions(
    val configPath: String,
    val engine: String = ENGINE_MIHOMO,
    val tunStack: String = STACK_GVISOR,
    /** Package names routed through the tunnel. Empty means "all apps". */
    val allowedApps: List<String> = emptyList(),
    /** Package names excluded from the tunnel. Ignored when [allowedApps] is set. */
    val disallowedApps: List<String> = emptyList(),
    val ipv6: Boolean = false,
    val bypassPrivateRoutes: Boolean = true,
    /** TLS ClientHello fragmentation. sing-box only; mihomo has no equivalent. */
    val tlsFragment: Boolean = false,
) {
    companion object {
        const val ENGINE_MIHOMO = "mihomo"
        const val ENGINE_SINGBOX = "singbox"

        const val STACK_GVISOR = "gvisor"
        const val STACK_SYSTEM = "system"
        const val STACK_MIXED = "mixed"
    }
}
