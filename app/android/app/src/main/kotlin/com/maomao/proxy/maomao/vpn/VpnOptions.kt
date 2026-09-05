package com.maomao.proxy.maomao.vpn

/** Parameters handed to [MaomaoVpnService] when starting the tunnel. */
data class VpnOptions(
    val configPath: String,
    val kernel: String = KERNEL_MIHOMO,
    val tunStack: String = STACK_GVISOR,
    /** Package names routed through the tunnel. Empty means "all apps". */
    val allowedApps: List<String> = emptyList(),
    /** Package names excluded from the tunnel. Ignored when [allowedApps] is set. */
    val disallowedApps: List<String> = emptyList(),
    val ipv6: Boolean = false,
    val bypassPrivateRoutes: Boolean = true,
) {
    companion object {
        const val KERNEL_MIHOMO = "mihomo"
        const val KERNEL_XRAY = "xray"

        const val STACK_GVISOR = "gvisor"
        const val STACK_SYSTEM = "system"
        const val STACK_MIXED = "mixed"
    }
}
