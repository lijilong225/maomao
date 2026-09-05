package bridge

import (
	"errors"
	"os"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func init() {
	registerEngine(&mihomoEngine{})
	registerLogPump(pumpMihomoLogs)
}

// mihomoEngine drives the embedded mihomo core. It holds no state of its own:
// mihomo keeps a single global instance, so every call goes through its hub.
type mihomoEngine struct{}

func (e *mihomoEngine) name() string { return EngineMihomo }

func (e *mihomoEngine) version() string { return C.Version }

func (e *mihomoEngine) validate(configPath string) error {
	_, err := e.parse(configPath)
	return err
}

// tunOptions reports the TUN parameters the host must mirror. The core narrows
// fake-ip-range to a /30, so the host cannot pick these freely.
func (e *mihomoEngine) tunOptions(configPath string) (tunOptions, error) {
	cfg, err := e.parse(configPath)
	if err != nil {
		return tunOptions{}, err
	}

	opts := tunOptions{MTU: cfg.General.Tun.MTU}
	if opts.MTU == 0 {
		opts.MTU = defaultTunMTU
	}
	if len(cfg.General.Tun.Inet4Address) > 0 {
		prefix := cfg.General.Tun.Inet4Address[0]
		opts.IPv4 = prefix.String()
		// The /30 leaves exactly two usable hosts: .1 for the gateway, .2 for DNS.
		if next := prefix.Addr().Next(); next.IsValid() && prefix.Contains(next) {
			opts.DNS = next.String()
		} else {
			opts.DNS = prefix.Addr().String()
		}
	}
	if len(cfg.General.Tun.Inet6Address) > 0 {
		opts.IPv6 = cfg.General.Tun.Inet6Address[0].String()
	}
	return opts, nil
}

func (e *mihomoEngine) start(opts startOptions, info controllerInfo) error {
	cfg, err := e.parse(opts.ConfigPath)
	if err != nil {
		return err
	}
	e.applyOverrides(cfg, opts, info)
	hub.ApplyConfig(cfg)
	return nil
}

// reload goes through the same path as start: mihomo swaps the running config
// in place and keeps the TUN descriptor it was handed.
func (e *mihomoEngine) reload(opts startOptions, info controllerInfo) error {
	return e.start(opts, info)
}

// shutdown stops the tunnel and gives up the controller address.
//
// executor.Shutdown only closes the TUN listener: the RESTful controller lives in
// hub/route's package globals and would keep its address bound for the rest of
// the process, so the core taking over could not claim it. hub/route exports no
// closer, but it does close the running server before honouring a new config, and
// an empty address stops it from starting a replacement.
func (e *mihomoEngine) shutdown() {
	executor.Shutdown()
	route.ReCreateServer(&route.Config{})
	awaitControllerRelease()
}

func (e *mihomoEngine) traffic() (int64, int64) {
	return statistic.DefaultManager.Now()
}

func (e *mihomoEngine) trafficTotal() (int64, int64) {
	return statistic.DefaultManager.Total()
}

func (e *mihomoEngine) parse(path string) (*config.Config, error) {
	if path == "" {
		return nil, errors.New("configPath is empty")
	}
	buf, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return executor.ParseWithBytes(buf)
}

// applyOverrides forces the settings the host owns, so a malicious or careless
// subscription cannot change how traffic is captured on the device.
func (e *mihomoEngine) applyOverrides(cfg *config.Config, opts startOptions, info controllerInfo) {
	cfg.Controller.ExternalController = info.Addr
	cfg.Controller.ExternalControllerTLS = ""
	cfg.Controller.ExternalControllerUnix = ""
	cfg.Controller.ExternalControllerPipe = ""
	cfg.Controller.ExternalUI = ""
	cfg.Controller.ExternalUIURL = ""
	cfg.Controller.ExternalDohServer = ""
	cfg.Controller.Secret = info.Secret

	// Routing on Android is owned by VpnService.Builder, and iptables needs root.
	cfg.IPTables.Enable = false

	switch {
	case opts.TunMode == TunModeAuto:
		cfg.General.Tun.Enable = true
		cfg.General.Tun.FileDescriptor = 0
		cfg.General.Tun.AutoRoute = true
		cfg.General.Tun.AutoDetectInterface = true
		cfg.General.Tun.AutoRedirect = false
	case opts.TunFd > 0:
		cfg.General.Tun.Enable = true
		cfg.General.Tun.FileDescriptor = opts.TunFd
		cfg.General.Tun.AutoRoute = false
		cfg.General.Tun.AutoRedirect = false
		cfg.General.Tun.AutoDetectInterface = false
		cfg.General.Tun.StrictRoute = false
	default:
		return
	}

	if stack, ok := C.StackTypeMapping[opts.TunStack]; ok {
		cfg.General.Tun.Stack = stack
	}
	if opts.TunMTU > 0 {
		cfg.General.Tun.MTU = opts.TunMTU
	}
	if len(cfg.General.Tun.DNSHijack) == 0 {
		cfg.General.Tun.DNSHijack = []string{"any:53"}
	}
}

// pumpMihomoLogs forwards the core's log bus to the host delegate. mihomo keeps
// the bus alive whether or not a config is applied, so this runs for the whole
// process lifetime even when another engine is selected.
func pumpMihomoLogs() {
	sub := log.Subscribe()
	defer log.UnSubscribe(sub)
	for event := range sub {
		emitLog(event.LogLevel.String(), event.Payload)
	}
}

// setMihomoHomeDir points the core at the host-provided working directory.
func setMihomoHomeDir(dir string) { C.SetHomeDir(dir) }
