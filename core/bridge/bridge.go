// Package bridge exposes a minimal, stable surface over the mihomo core so it can be
// embedded into host applications (Android via gomobile, desktop via c-shared).
package bridge

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"sync"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// State values reported through Delegate.OnState.
const (
	StateStopped  = "stopped"
	StateStarting = "starting"
	StateRunning  = "running"
)

// defaultTunMTU mirrors the fallback used by the core's sing-tun listener.
const defaultTunMTU = 9000

// Delegate lets the host platform provide capabilities the core cannot reach on its own.
// Method signatures must stay gomobile-compatible (basic types only).
type Delegate interface {
	// Protect excludes a socket from the VPN tunnel. Android only; return true on success.
	Protect(fd int32) bool
	// OnLog receives core log events. level is one of debug/info/warning/error.
	OnLog(level string, payload string)
	// OnState receives lifecycle transitions.
	OnState(state string)
}

// startOptions is the JSON payload accepted by Start. Kept unexported because
// gomobile cannot bind structs with unsigned integer fields.
type startOptions struct {
	ConfigPath string `json:"configPath"`
	// TunFd is the file descriptor produced by VpnService.establish(). 0 disables TUN.
	TunFd int `json:"tunFd"`
	// TunStack is gvisor, system or mixed.
	TunStack string `json:"tunStack"`
	TunMTU   uint32 `json:"tunMTU"`
}

type controllerInfo struct {
	Addr   string `json:"addr"`
	Secret string `json:"secret"`
}

var (
	mu       sync.Mutex
	delegate Delegate
	state    = StateStopped

	current    startOptions
	controller controllerInfo

	logOnce sync.Once
)

// Init prepares the core working directories. Must be called once before Start.
func Init(homeDir string) error {
	if homeDir == "" {
		return errors.New("homeDir is empty")
	}
	if err := os.MkdirAll(homeDir, 0o700); err != nil {
		return err
	}
	C.SetHomeDir(homeDir)
	return nil
}

// RegisterDelegate installs the host callbacks and starts forwarding core logs.
func RegisterDelegate(d Delegate) {
	mu.Lock()
	delegate = d
	mu.Unlock()

	installSocketHook()
	logOnce.Do(func() { go pumpLogs() })
}

// Version reports the embedded mihomo version.
func Version() string { return C.Version }

// State reports the current core lifecycle state.
func State() string {
	mu.Lock()
	defer mu.Unlock()
	return state
}

// ControllerInfo returns {"addr","secret"} for the loopback RESTful controller.
func ControllerInfo() string {
	mu.Lock()
	defer mu.Unlock()
	buf, _ := json.Marshal(controller)
	return string(buf)
}

// ValidateConfig parses a config file without applying it.
func ValidateConfig(configPath string) error {
	_, err := parseConfigFile(configPath)
	return err
}

// tunOptions describes the parameters the host must mirror when building the
// platform TUN interface, so it matches what the core will bind to.
type tunOptions struct {
	IPv4 string `json:"ipv4"`
	IPv6 string `json:"ipv6"`
	MTU  uint32 `json:"mtu"`
	DNS  string `json:"dns"`
}

// TunOptions inspects a config file and reports the TUN parameters as JSON.
// The core narrows fake-ip-range to a /30, so the host cannot pick these freely.
func TunOptions(configPath string) (string, error) {
	cfg, err := parseConfigFile(configPath)
	if err != nil {
		return "", err
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

	buf, err := json.Marshal(opts)
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

// Start applies the config and brings the tunnel up.
func Start(optionsJSON string) error {
	var opts startOptions
	if err := json.Unmarshal([]byte(optionsJSON), &opts); err != nil {
		return fmt.Errorf("invalid options: %w", err)
	}

	cfg, err := parseConfigFile(opts.ConfigPath)
	if err != nil {
		return err
	}

	mu.Lock()
	if controller.Secret == "" {
		addr, secret, aErr := allocController()
		if aErr != nil {
			mu.Unlock()
			return aErr
		}
		controller = controllerInfo{Addr: addr, Secret: secret}
	}
	info := controller
	current = opts
	mu.Unlock()

	setState(StateStarting)
	applyOverrides(cfg, opts, info)
	hub.ApplyConfig(cfg)
	setState(StateRunning)
	return nil
}

// Reload re-applies a config file while keeping the existing TUN descriptor.
func Reload(configPath string) error {
	mu.Lock()
	opts := current
	info := controller
	running := state == StateRunning
	mu.Unlock()

	if !running {
		return errors.New("core is not running")
	}
	if configPath != "" {
		opts.ConfigPath = configPath
	}

	cfg, err := parseConfigFile(opts.ConfigPath)
	if err != nil {
		return err
	}

	applyOverrides(cfg, opts, info)
	hub.ApplyConfig(cfg)

	mu.Lock()
	current = opts
	mu.Unlock()
	return nil
}

// Stop tears the tunnel down. The TUN descriptor is closed by the core.
func Stop() {
	mu.Lock()
	running := state != StateStopped
	current = startOptions{}
	mu.Unlock()

	if running {
		executor.Shutdown()
	}
	setState(StateStopped)
}

// Traffic returns {"up","down"} in bytes per second.
func Traffic() string {
	up, down := statistic.DefaultManager.Now()
	buf, _ := json.Marshal(map[string]int64{"up": up, "down": down})
	return string(buf)
}

// TrafficTotal returns cumulative {"up","down"} in bytes since start.
func TrafficTotal() string {
	up, down := statistic.DefaultManager.Total()
	buf, _ := json.Marshal(map[string]int64{"up": up, "down": down})
	return string(buf)
}

func parseConfigFile(path string) (*config.Config, error) {
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
func applyOverrides(cfg *config.Config, opts startOptions, info controllerInfo) {
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

	if opts.TunFd > 0 {
		cfg.General.Tun.Enable = true
		cfg.General.Tun.FileDescriptor = opts.TunFd
		cfg.General.Tun.AutoRoute = false
		cfg.General.Tun.AutoRedirect = false
		cfg.General.Tun.AutoDetectInterface = false
		cfg.General.Tun.StrictRoute = false
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
}

func allocController() (string, string, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", "", err
	}
	port := l.Addr().(*net.TCPAddr).Port
	if err := l.Close(); err != nil {
		return "", "", err
	}

	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", "", err
	}
	return fmt.Sprintf("127.0.0.1:%d", port), hex.EncodeToString(raw), nil
}

func setState(s string) {
	mu.Lock()
	state = s
	d := delegate
	mu.Unlock()

	if d != nil {
		d.OnState(s)
	}
}

func pumpLogs() {
	sub := log.Subscribe()
	defer log.UnSubscribe(sub)
	for event := range sub {
		mu.Lock()
		d := delegate
		mu.Unlock()
		if d == nil {
			continue
		}
		d.OnLog(event.LogLevel.String(), event.Payload)
	}
}
