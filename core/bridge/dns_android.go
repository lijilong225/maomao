//go:build android && cmfa

package bridge

import "github.com/metacubex/mihomo/dns"

// The cmfa build tag replaces mihomo's resolv.conf reader with a slot the host
// must fill, so the system resolver is empty until SetSystemDNS is called.
func updateSystemDNS(servers []string) {
	dns.UpdateSystemDNS(servers)
}
