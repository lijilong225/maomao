package bridge

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"os"
	"sync"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// defaultTunMTU mirrors the fallback used by mihomo's sing-tun listener.
const defaultTunMTU = 9000

// mihomoCore is the mihomo engine. mihomo keeps its state in package-level
// globals, so a single instance is the only correct shape.
var mihomoCore = &mihomoKernel{}

type mihomoKernel struct {
	mu         sync.Mutex
	controller controllerInfo
}

func (k *mihomoKernel) name() string { return KernelMihomo }

func (k *mihomoKernel) version() string { return C.Version }

func (k *mihomoKernel) validateConfig(configPath string) error {
	_, err := k.parseConfigFile(configPath)
	return err
}

// tunOptions inspects a config file and reports the TUN parameters.
// mihomo narrows fake-ip-range to a /30, so the host cannot pick these freely.
func (k *mihomoKernel) tunOptions(configPath string) (tunOptions, error) {
	cfg, err := k.parseConfigFile(configPath)
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

func (k *mihomoKernel) start(opts startOptions) error {
	cfg, err := k.parseConfigFile(opts.ConfigPath)
	if err != nil {
		return err
	}

	info, err := k.ensureController()
	if err != nil {
		return err
	}

	k.applyOverrides(cfg, opts, info)
	hub.ApplyConfig(cfg)
	return nil
}

func (k *mihomoKernel) reload(opts startOptions) error {
	cfg, err := k.parseConfigFile(opts.ConfigPath)
	if err != nil {
		return err
	}

	k.mu.Lock()
	info := k.controller
	k.mu.Unlock()

	k.applyOverrides(cfg, opts, info)
	hub.ApplyConfig(cfg)
	return nil
}

func (k *mihomoKernel) stop() { executor.Shutdown() }

func (k *mihomoKernel) controllerInfo() controllerInfo {
	k.mu.Lock()
	defer k.mu.Unlock()
	return k.controller
}

func (k *mihomoKernel) traffic() trafficStat {
	up, down := statistic.DefaultManager.Now()
	return trafficStat{Up: up, Down: down}
}

func (k *mihomoKernel) trafficTotal() trafficStat {
	up, down := statistic.DefaultManager.Total()
	return trafficStat{Up: up, Down: down}
}

func (k *mihomoKernel) parseConfigFile(path string) (*config.Config, error) {
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
func (k *mihomoKernel) applyOverrides(cfg *config.Config, opts startOptions, info controllerInfo) {
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

// ensureController allocates the loopback API endpoint on first start and reuses
// it afterwards, so a reconnect does not invalidate the host's cached URL.
func (k *mihomoKernel) ensureController() (controllerInfo, error) {
	k.mu.Lock()
	defer k.mu.Unlock()

	if k.controller.Secret != "" {
		return k.controller, nil
	}

	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return controllerInfo{}, err
	}
	port := l.Addr().(*net.TCPAddr).Port
	if err := l.Close(); err != nil {
		return controllerInfo{}, err
	}

	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return controllerInfo{}, err
	}

	k.controller = controllerInfo{
		Addr:   fmt.Sprintf("127.0.0.1:%d", port),
		Secret: hex.EncodeToString(raw),
	}
	return k.controller, nil
}
