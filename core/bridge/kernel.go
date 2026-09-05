package bridge

import "fmt"

// Kernel identifiers accepted by Start.
const (
	KernelMihomo = "mihomo"
	KernelXray   = "xray"
)

// startOptions is the JSON payload accepted by Start. Kept unexported because
// gomobile cannot bind structs with unsigned integer fields.
type startOptions struct {
	// Kernel selects the proxy engine. Empty means KernelMihomo, so hosts that
	// predate the dual-kernel support keep working unchanged.
	Kernel     string `json:"kernel"`
	ConfigPath string `json:"configPath"`
	// TunFd is the file descriptor produced by VpnService.establish(). 0 disables TUN.
	TunFd int `json:"tunFd"`
	// TunStack is gvisor, system or mixed.
	TunStack string `json:"tunStack"`
	TunMTU   uint32 `json:"tunMTU"`
	// TunMode is TunModeFD (default) or TunModeAuto.
	TunMode string `json:"tunMode"`
	// XrayFragment splits outgoing TLS handshakes. mihomo ignores it.
	XrayFragment bool `json:"xrayFragment"`
}

func (o startOptions) kernelName() string {
	if o.Kernel == "" {
		return KernelMihomo
	}
	return o.Kernel
}

type controllerInfo struct {
	Addr   string `json:"addr"`
	Secret string `json:"secret"`
}

type trafficStat struct {
	Up   int64 `json:"up"`
	Down int64 `json:"down"`
}

// tunOptions describes the parameters the host must mirror when building the
// platform TUN interface, so it matches what the engine will bind to.
type tunOptions struct {
	IPv4 string `json:"ipv4"`
	IPv6 string `json:"ipv6"`
	MTU  uint32 `json:"mtu"`
	DNS  string `json:"dns"`
}

// kernel is one proxy engine. Implementations own their config translation and
// their own lifecycle; the bridge owns the state machine and the host callbacks.
type kernel interface {
	// name is the identifier accepted by startOptions.Kernel.
	name() string
	// version reports the engine version.
	version() string
	// validateConfig parses a config file without applying it.
	validateConfig(configPath string) error
	// tunOptions reports the TUN parameters a config file resolves to.
	tunOptions(configPath string) (tunOptions, error)
	// start applies the config and brings the tunnel up.
	start(opts startOptions) error
	// reload re-applies a config without rebuilding the TUN interface.
	reload(opts startOptions) error
	// stop tears the tunnel down.
	stop()
	// controllerInfo describes the engine's loopback RESTful API. Engines without
	// one return a zero value, and the host must fall back to the bridge calls.
	controllerInfo() controllerInfo
	// traffic reports the current rate in bytes per second.
	traffic() trafficStat
	// trafficTotal reports cumulative bytes since the engine started.
	trafficTotal() trafficStat
}

func resolveKernel(name string) (kernel, error) {
	switch name {
	case KernelMihomo:
		return mihomoCore, nil
	case KernelXray:
		return xrayCore, nil
	default:
		return nil, fmt.Errorf("unsupported kernel %q", name)
	}
}
