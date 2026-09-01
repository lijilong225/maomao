//go:build !(android && cmfa)

package bridge

// On other builds mihomo reads the system resolvers itself.
func updateSystemDNS(servers []string) {}
