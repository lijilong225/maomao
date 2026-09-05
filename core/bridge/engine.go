package bridge

import (
	"errors"
	"fmt"
	"sync"
)

// Engine identifiers accepted by Start.
const (
	// EngineMihomo is the default engine and consumes Clash/mihomo YAML directly.
	EngineMihomo = "mihomo"
	// EngineSingbox consumes sing-box JSON; subscriptions must be converted first.
	EngineSingbox = "singbox"
)

// engine isolates the parts of the tunnel lifecycle that differ between cores,
// so bridge.go can own the state machine, the controller credentials and the
// delegate plumbing regardless of which core is selected.
//
// Implementations are not required to be goroutine safe: bridge.go serialises
// every call through the package mutex or through the exported entry points.
type engine interface {
	// name reports the engine identifier used on the wire.
	name() string
	// version reports the embedded core version.
	version() string
	// validate parses a config file without applying it.
	validate(configPath string) error
	// tunOptions reports the TUN parameters the host must mirror when it builds
	// the platform interface.
	tunOptions(configPath string) (tunOptions, error)
	// start applies the config and brings the tunnel up.
	start(opts startOptions, info controllerInfo) error
	// reload re-applies a config while keeping the existing TUN descriptor.
	reload(opts startOptions, info controllerInfo) error
	// shutdown tears the tunnel down. Must tolerate being called when stopped.
	shutdown()
	// traffic reports the current rate in bytes per second.
	traffic() (up int64, down int64)
	// trafficTotal reports cumulative bytes since the tunnel came up.
	trafficTotal() (up int64, down int64)
}

var (
	engineMu sync.Mutex
	engines  = map[string]engine{}
)

// registerEngine installs an implementation. Called from the per-engine init.
func registerEngine(e engine) {
	engineMu.Lock()
	defer engineMu.Unlock()
	engines[e.name()] = e
}

// normalizeEngine maps an empty or unknown identifier onto the default engine.
func normalizeEngine(name string) string {
	if name == "" {
		return EngineMihomo
	}
	return name
}

// NormalizedEngine resolves the identifier the host passed into the one Start
// will actually use, so hosts can compare it against ActiveEngine.
func NormalizedEngine(name string) string { return normalizeEngine(name) }

// lookupEngine resolves an engine identifier.
func lookupEngine(name string) (engine, error) {
	name = normalizeEngine(name)

	engineMu.Lock()
	defer engineMu.Unlock()
	e, ok := engines[name]
	if !ok {
		return nil, fmt.Errorf("unknown engine: %s", name)
	}
	return e, nil
}

// errNotRunning is reported when a reload is requested while stopped.
var errNotRunning = errors.New("core is not running")
