// Package bridge exposes a minimal, stable surface over the proxy kernels so they
// can be embedded into host applications (Android via gomobile, desktop via the
// maomao-core sidecar). It owns the lifecycle state machine and the host
// callbacks; each kernel owns its own config translation.
package bridge

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
)

// State values reported through Delegate.OnState.
const (
	StateStopped  = "stopped"
	StateStarting = "starting"
	StateRunning  = "running"
)

// TUN modes accepted by Start.
const (
	// TunModeFD binds the descriptor handed over by the host, which owns routing.
	TunModeFD = "fd"
	// TunModeAuto lets the kernel create the interface and install the routes
	// itself. Used by desktop hosts; needs administrator rights on Windows.
	TunModeAuto = "auto"
)

// Delegate lets the host platform provide capabilities the kernel cannot reach on its own.
// Method signatures must stay gomobile-compatible (basic types only).
type Delegate interface {
	// Protect excludes a socket from the VPN tunnel. Android only; return true on success.
	Protect(fd int32) bool
	// OnLog receives kernel log events. level is one of debug/info/warning/error.
	OnLog(level string, payload string)
	// OnState receives lifecycle transitions.
	OnState(state string)
}

var (
	mu       sync.Mutex
	delegate Delegate
	state    = StateStopped

	current startOptions
	// selected survives Stop so the host can query versions and validate configs
	// against the kernel it last chose.
	selected kernel = mihomoCore

	logOnce sync.Once
)

// Init prepares the kernel working directories. Must be called once before Start.
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

// RegisterDelegate installs the host callbacks and starts forwarding kernel logs.
func RegisterDelegate(d Delegate) {
	mu.Lock()
	delegate = d
	mu.Unlock()

	installSocketHook()
	logOnce.Do(func() { go pumpLogs() })
}

// SelectKernel switches the active kernel without starting it, so the host can
// query versions and validate configs before connecting. Rejected while running,
// because the tunnel would have to be rebuilt anyway.
func SelectKernel(name string) error {
	k, err := resolveKernel(name)
	if err != nil {
		return err
	}

	mu.Lock()
	defer mu.Unlock()
	if k != selected && state != StateStopped {
		return errors.New("cannot switch kernel while running")
	}
	selected = k
	return nil
}

// Kernel reports the identifier of the active kernel.
func Kernel() string { return activeKernel().name() }

// Version reports the version of the active kernel.
func Version() string { return activeKernel().version() }

// SetSystemDNS hands the platform resolvers to the kernel. On Android the kernel
// cannot read /etc/resolv.conf, so without this every hostname it resolves
// outside the tunnel fails, including the geoip/geosite downloads that run while
// a config is being parsed. servers is a comma-separated list of addresses; a
// missing port defaults to 53. An empty value clears the list.
func SetSystemDNS(servers string) {
	var addrs []string
	for _, raw := range strings.Split(servers, ",") {
		addr := strings.TrimSpace(raw)
		if addr == "" {
			continue
		}
		// net.SplitHostPort rejects bare addresses, and IPv6 literals must stay
		// bracketed for the kernel's own parsing.
		if _, _, err := net.SplitHostPort(addr); err != nil {
			addr = net.JoinHostPort(addr, "53")
		}
		addrs = append(addrs, addr)
	}
	updateSystemDNS(addrs)
}

// State reports the current lifecycle state.
func State() string {
	mu.Lock()
	defer mu.Unlock()
	return state
}

// ControllerInfo returns {"addr","secret"} for the loopback RESTful controller.
// Both fields are empty for kernels that do not expose one.
func ControllerInfo() string {
	buf, _ := json.Marshal(activeKernel().controllerInfo())
	return string(buf)
}

// ValidateConfig parses a config file without applying it.
func ValidateConfig(configPath string) error {
	return activeKernel().validateConfig(configPath)
}

// TunOptions inspects a config file and reports the TUN parameters as JSON.
func TunOptions(configPath string) (string, error) {
	opts, err := activeKernel().tunOptions(configPath)
	if err != nil {
		return "", err
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

	k, err := resolveKernel(opts.kernelName())
	if err != nil {
		return err
	}

	// Announced before the parse so the UI can react on the first frame; parsing a
	// large config takes long enough to look like a stalled tap otherwise.
	setState(StateStarting)

	mu.Lock()
	selected = k
	mu.Unlock()

	if err := k.start(opts); err != nil {
		setState(StateStopped)
		return err
	}

	mu.Lock()
	current = opts
	mu.Unlock()

	setState(StateRunning)
	return nil
}

// Reload re-applies a config file while keeping the existing TUN descriptor.
func Reload(configPath string) error {
	mu.Lock()
	opts := current
	k := selected
	running := state == StateRunning
	mu.Unlock()

	if !running {
		return errors.New("core is not running")
	}
	if configPath != "" {
		opts.ConfigPath = configPath
	}

	if err := k.reload(opts); err != nil {
		return err
	}

	mu.Lock()
	current = opts
	mu.Unlock()
	return nil
}

// Stop tears the tunnel down. The TUN descriptor is closed by the kernel.
func Stop() {
	mu.Lock()
	running := state != StateStopped
	k := selected
	current = startOptions{}
	mu.Unlock()

	if running {
		k.stop()
	}
	setState(StateStopped)
}

// Traffic returns {"up","down"} in bytes per second.
func Traffic() string {
	buf, _ := json.Marshal(activeKernel().traffic())
	return string(buf)
}

// TrafficTotal returns cumulative {"up","down"} in bytes since start.
func TrafficTotal() string {
	buf, _ := json.Marshal(activeKernel().trafficTotal())
	return string(buf)
}

func activeKernel() kernel {
	mu.Lock()
	defer mu.Unlock()
	return selected
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
