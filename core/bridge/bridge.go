// Package bridge exposes a minimal, stable surface over the proxy cores so they
// can be embedded into host applications (Android via gomobile, desktop via a
// sidecar process). Two cores live behind the same surface: mihomo, which
// consumes Clash YAML, and sing-box, which consumes its own JSON.
package bridge

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

// State values reported through Delegate.OnState.
const (
	StateStopped  = "stopped"
	StateStarting = "starting"
	StateRunning  = "running"
)

// defaultTunMTU mirrors the fallback used by the cores' TUN listeners.
const defaultTunMTU = 9000

// TUN modes accepted by Start.
const (
	// TunModeFD binds the descriptor handed over by the host, which owns routing.
	TunModeFD = "fd"
	// TunModeAuto lets the core create the interface and install the routes
	// itself. Used by desktop hosts; needs administrator rights on Windows.
	TunModeAuto = "auto"
)

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
	// Engine selects the core: EngineMihomo (default) or EngineSingbox.
	Engine     string `json:"engine"`
	ConfigPath string `json:"configPath"`
	// TunFd is the file descriptor produced by VpnService.establish(). 0 disables TUN.
	TunFd int `json:"tunFd"`
	// TunStack is gvisor, system or mixed.
	TunStack string `json:"tunStack"`
	TunMTU   uint32 `json:"tunMTU"`
	// TunMode is TunModeFD (default) or TunModeAuto.
	TunMode string `json:"tunMode"`
	// TLSFragment splits the TLS ClientHello so a censor cannot read the SNI from
	// a single packet. sing-box only; mihomo has no equivalent.
	TLSFragment bool `json:"tlsFragment"`
}

type controllerInfo struct {
	Addr   string `json:"addr"`
	Secret string `json:"secret"`
}

// tunOptions describes the parameters the host must mirror when building the
// platform TUN interface, so it matches what the core will bind to.
type tunOptions struct {
	IPv4 string `json:"ipv4"`
	IPv6 string `json:"ipv6"`
	MTU  uint32 `json:"mtu"`
	DNS  string `json:"dns"`
}

var (
	mu       sync.Mutex
	delegate Delegate
	state    = StateStopped

	current    startOptions
	controller controllerInfo
	// active is the engine that owns the live tunnel, nil while stopped.
	active engine

	homeDir string

	logOnce  sync.Once
	logPumps []func()
)

// registerLogPump installs a goroutine body that forwards one core's log bus to
// the delegate. Called from the per-engine init; started by RegisterDelegate.
func registerLogPump(pump func()) {
	logPumps = append(logPumps, pump)
}

// Init prepares the core working directories. Must be called once before Start.
func Init(dir string) error {
	if dir == "" {
		return errors.New("homeDir is empty")
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	mu.Lock()
	homeDir = dir
	mu.Unlock()

	setMihomoHomeDir(dir)
	return nil
}

// RegisterDelegate installs the host callbacks and starts forwarding core logs.
func RegisterDelegate(d Delegate) {
	mu.Lock()
	delegate = d
	mu.Unlock()

	installSocketHook()
	logOnce.Do(func() {
		for _, pump := range logPumps {
			go pump()
		}
	})
}

// Version reports the version of the engine that owns the tunnel, falling back
// to the engine that would be selected by default.
func Version() string {
	mu.Lock()
	e := active
	name := current.Engine
	mu.Unlock()

	if e != nil {
		return e.version()
	}
	return VersionOf(name)
}

// VersionOf reports the version embedded for a specific engine. An empty name
// selects the default engine; an unknown name yields an empty string.
func VersionOf(name string) string {
	e, err := lookupEngine(name)
	if err != nil {
		return ""
	}
	return e.version()
}

// SetSystemDNS hands the platform resolvers to the core. On Android the core
// cannot read /etc/resolv.conf, so without this every hostname the core resolves
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
		// bracketed for the core's own parsing.
		if _, _, err := net.SplitHostPort(addr); err != nil {
			addr = net.JoinHostPort(addr, "53")
		}
		addrs = append(addrs, addr)
	}
	updateSystemDNS(addrs)
}

// State reports the current core lifecycle state.
func State() string {
	mu.Lock()
	defer mu.Unlock()
	return state
}

// ActiveEngine reports the engine that owns the live tunnel, or an empty string
// while stopped. Hosts use it to decide between a reload and a full restart,
// because a reload cannot move a tunnel from one core to the other.
func ActiveEngine() string {
	mu.Lock()
	defer mu.Unlock()
	if active == nil {
		return ""
	}
	return active.name()
}

// ControllerInfo returns {"addr","secret"} for the loopback RESTful controller.
func ControllerInfo() string {
	mu.Lock()
	defer mu.Unlock()
	buf, _ := json.Marshal(controller)
	return string(buf)
}

// ValidateConfig parses a config file with the given engine without applying it.
// An empty engine name selects the default engine.
func ValidateConfig(engineName string, configPath string) error {
	e, err := lookupEngine(engineName)
	if err != nil {
		return err
	}
	return e.validate(configPath)
}

// TunOptions inspects a config file and reports the TUN parameters as JSON.
// The core narrows the interface address to a /30, so the host cannot pick these
// freely and has to mirror whatever is reported here.
func TunOptions(engineName string, configPath string) (string, error) {
	e, err := lookupEngine(engineName)
	if err != nil {
		return "", err
	}
	opts, err := e.tunOptions(configPath)
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
	opts.Engine = normalizeEngine(opts.Engine)

	next, err := lookupEngine(opts.Engine)
	if err != nil {
		return err
	}

	// Announced before the parse so the UI can react on the first frame; parsing a
	// large config takes long enough to look like a stalled tap otherwise.
	setState(StateStarting)

	mu.Lock()
	previous := active
	if controller.Secret == "" {
		addr, secret, aErr := allocController()
		if aErr != nil {
			mu.Unlock()
			setState(StateStopped)
			return aErr
		}
		controller = controllerInfo{Addr: addr, Secret: secret}
	}
	info := controller
	mu.Unlock()

	// Two cores must never be live at once: they would fight over the same TUN
	// descriptor and controller port.
	if previous != nil && previous != next {
		previous.shutdown()
		mu.Lock()
		active = nil
		mu.Unlock()
	}

	if err := next.start(opts, info); err != nil {
		setState(StateStopped)
		return err
	}

	mu.Lock()
	current = opts
	active = next
	mu.Unlock()

	setState(StateRunning)
	return nil
}

// Reload re-applies a config file while keeping the existing TUN descriptor.
func Reload(configPath string) error {
	mu.Lock()
	opts := current
	info := controller
	e := active
	isRunning := state == StateRunning
	mu.Unlock()

	if !isRunning || e == nil {
		return errNotRunning
	}
	if configPath != "" {
		opts.ConfigPath = configPath
	}

	if err := e.reload(opts, info); err != nil {
		return err
	}

	mu.Lock()
	current = opts
	mu.Unlock()
	return nil
}

// Stop tears the tunnel down, releasing the TUN descriptor handed over by the
// host: mihomo adopts it directly, while sing-box works on duplicates and leaves
// the original to the engine's shutdown.
func Stop() {
	mu.Lock()
	e := active
	wasRunning := state != StateStopped
	current = startOptions{}
	active = nil
	mu.Unlock()

	if wasRunning && e != nil {
		e.shutdown()
	}
	setState(StateStopped)
}

// Traffic returns {"up","down"} in bytes per second.
func Traffic() string {
	return marshalTraffic(func(e engine) (int64, int64) { return e.traffic() })
}

// TrafficTotal returns cumulative {"up","down"} in bytes since start.
func TrafficTotal() string {
	return marshalTraffic(func(e engine) (int64, int64) { return e.trafficTotal() })
}

func marshalTraffic(read func(engine) (int64, int64)) string {
	mu.Lock()
	e := active
	mu.Unlock()

	var up, down int64
	if e != nil {
		up, down = read(e)
	}
	buf, _ := json.Marshal(map[string]int64{"up": up, "down": down})
	return string(buf)
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

// controllerReleaseTimeout bounds the wait for a closing controller listener.
// Dropping a loopback listener is immediate, so a longer wait would only mean the
// address is held by something the bridge does not own.
const controllerReleaseTimeout = time.Second

// awaitControllerRelease blocks until the controller address can be bound again.
//
// Cores tear their listener down from a goroutine, so a shutdown returning is not
// enough for the next core to claim the address, and the address is fixed for the
// life of the process. Best effort: if it stays taken there is nothing useful to
// do here, and the core that fails to bind reports it itself.
func awaitControllerRelease() {
	mu.Lock()
	addr := controller.Addr
	mu.Unlock()
	if addr == "" {
		return
	}

	deadline := time.Now().Add(controllerReleaseTimeout)
	for {
		l, err := net.Listen("tcp", addr)
		if err == nil {
			_ = l.Close()
			return
		}
		if !time.Now().Before(deadline) {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
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

// emitLog forwards one core log line to the host, dropping it while no delegate
// is attached.
func emitLog(level string, payload string) {
	mu.Lock()
	d := delegate
	mu.Unlock()

	if d == nil {
		return
	}
	d.OnLog(level, payload)
}

// currentHomeDir reports the working directory handed to Init. Engines that keep
// their own state on disk derive their paths from it.
func currentHomeDir() string {
	mu.Lock()
	defer mu.Unlock()
	return homeDir
}
