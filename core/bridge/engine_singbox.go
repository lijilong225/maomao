package bridge

import (
	"context"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"sync"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/common/trafficcontrol"
	sbconstant "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	sblog "github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	sbjson "github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/service"
)

func init() {
	registerEngine(&singboxEngine{})
}

// defaultSingboxTunAddress mirrors what the sing-box docs suggest and what the
// Android host falls back to when a config omits the TUN address.
const defaultSingboxTunAddress = "172.19.0.1/30"

// singboxEngine drives the embedded sing-box core.
//
// Unlike mihomo, sing-box has no global instance: every config produces a fresh
// *box.Box with its own service registry, so the engine has to own that state.
// bridge.go serialises lifecycle calls, but traffic() is polled from a host timer
// concurrently, hence the mutex.
type singboxEngine struct {
	mu       sync.Mutex
	instance *box.Box
	// ctx carries the service registry of the live instance. Traffic counters are
	// read back out of it, so it has to be kept alongside the instance.
	ctx context.Context

	// Rate is derived by differentiating the cumulative counters: sing-box only
	// exposes totals, unlike mihomo which tracks a rate itself.
	lastUp   int64
	lastDown int64
	lastAt   time.Time
	rateUp   int64
	rateDown int64
}

func (e *singboxEngine) name() string { return EngineSingbox }

func (e *singboxEngine) version() string { return sbconstant.Version }

func (e *singboxEngine) validate(configPath string) error {
	ctx, opts, err := e.parse(configPath, startOptions{})
	if err != nil {
		return err
	}
	// Only a full construction catches the errors that matter: unknown outbound
	// references, duplicate tags, unusable TLS material.
	instance, err := box.New(box.Options{Context: ctx, Options: opts})
	if err != nil {
		return err
	}
	return instance.Close()
}

// tunOptions reports the TUN parameters the Android host must mirror on
// VpnService.Builder, taken from the config's own tun inbound.
func (e *singboxEngine) tunOptions(configPath string) (tunOptions, error) {
	_, opts, err := e.parse(configPath, startOptions{})
	if err != nil {
		return tunOptions{}, err
	}

	tun := findTunInbound(&opts)
	if tun == nil {
		return tunOptions{}, errors.New("config has no tun inbound")
	}

	out := tunOptions{MTU: tun.MTU}
	if out.MTU == 0 {
		out.MTU = defaultTunMTU
	}
	for _, prefix := range tun.Address {
		if prefix.Addr().Is4() && out.IPv4 == "" {
			out.IPv4 = prefix.String()
			continue
		}
		if prefix.Addr().Is6() && out.IPv6 == "" {
			out.IPv6 = prefix.String()
		}
	}
	out.DNS = singboxTunDNS(tun)
	return out, nil
}

func (e *singboxEngine) start(opts startOptions, info controllerInfo) error {
	instance, ctx, err := e.build(opts, info)
	if err != nil {
		return err
	}
	// Start already closes the instance on failure, so it must not be closed again.
	if err := instance.Start(); err != nil {
		return err
	}

	e.mu.Lock()
	previous := e.instance
	e.instance = instance
	e.ctx = ctx
	e.resetRateLocked()
	e.mu.Unlock()

	if previous != nil {
		_ = previous.Close()
	}
	return nil
}

// reload builds the replacement before retiring the old instance, so a bad
// config leaves the running tunnel untouched.
//
// The new instance gets a brand new context: service registries are mutated in
// place, so reusing one would let the new instance overwrite services the old one
// is still reading from while it shuts down.
func (e *singboxEngine) reload(opts startOptions, info controllerInfo) error {
	return e.start(opts, info)
}

func (e *singboxEngine) shutdown() {
	e.mu.Lock()
	instance := e.instance
	e.instance = nil
	e.ctx = nil
	e.resetRateLocked()
	e.mu.Unlock()

	if instance != nil {
		_ = instance.Close()
	}
}

func (e *singboxEngine) traffic() (int64, int64) {
	up, down := e.trafficTotal()

	e.mu.Lock()
	defer e.mu.Unlock()

	now := time.Now()
	// Guard against the counters being read twice within the same tick, and
	// against a restart resetting them below the previous sample.
	if elapsed := now.Sub(e.lastAt); e.lastAt.IsZero() || elapsed < 100*time.Millisecond {
		if e.lastAt.IsZero() {
			e.lastAt, e.lastUp, e.lastDown = now, up, down
		}
		return e.rateUp, e.rateDown
	} else {
		seconds := elapsed.Seconds()
		e.rateUp = perSecond(up-e.lastUp, seconds)
		e.rateDown = perSecond(down-e.lastDown, seconds)
		e.lastAt, e.lastUp, e.lastDown = now, up, down
	}
	return e.rateUp, e.rateDown
}

func (e *singboxEngine) trafficTotal() (int64, int64) {
	e.mu.Lock()
	ctx := e.ctx
	e.mu.Unlock()

	if ctx == nil {
		return 0, 0
	}
	manager := service.PtrFromContext[trafficcontrol.Manager](ctx)
	if manager == nil {
		return 0, 0
	}
	return manager.Total()
}

func (e *singboxEngine) resetRateLocked() {
	e.lastUp, e.lastDown = 0, 0
	e.lastAt = time.Time{}
	e.rateUp, e.rateDown = 0, 0
}

func perSecond(delta int64, seconds float64) int64 {
	if delta <= 0 || seconds <= 0 {
		return 0
	}
	return int64(float64(delta) / seconds)
}

// build parses the config and constructs an instance without starting it.
func (e *singboxEngine) build(opts startOptions, info controllerInfo) (*box.Box, context.Context, error) {
	ctx, parsed, err := e.parse(opts.ConfigPath, opts)
	if err != nil {
		return nil, nil, err
	}
	applySingboxOverrides(&parsed, opts, info)

	instance, err := box.New(box.Options{
		Context:           ctx,
		Options:           parsed,
		PlatformLogWriter: singboxLogWriter{},
	})
	if err != nil {
		return nil, nil, err
	}
	return instance, ctx, nil
}

// parse reads a config file and returns it along with the context carrying the
// registries its unmarshalling depends on.
//
// Every call builds a fresh context on purpose: registries are mutable, so an
// instance must never share one with another instance.
func (e *singboxEngine) parse(configPath string, opts startOptions) (context.Context, option.Options, error) {
	if configPath == "" {
		return nil, option.Options{}, errors.New("configPath is empty")
	}
	buf, err := os.ReadFile(configPath)
	if err != nil {
		return nil, option.Options{}, err
	}

	ctx := include.Context(context.Background())
	ctx = withSingboxPlatform(ctx, opts)

	parsed, err := sbjson.UnmarshalExtendedContext[option.Options](ctx, buf)
	if err != nil {
		return nil, option.Options{}, fmt.Errorf("invalid sing-box config: %w", err)
	}
	return ctx, parsed, nil
}

// applySingboxOverrides forces the settings the host owns, so a subscription
// cannot change how traffic is captured or expose the controller.
func applySingboxOverrides(opts *option.Options, start startOptions, info controllerInfo) {
	if opts.Experimental == nil {
		opts.Experimental = &option.ExperimentalOptions{}
	}
	if opts.Experimental.ClashAPI == nil {
		opts.Experimental.ClashAPI = &option.ClashAPIOptions{}
	}
	clash := opts.Experimental.ClashAPI
	clash.ExternalController = info.Addr
	clash.Secret = info.Secret
	// The app ships its own UI, and letting a config download one would mean
	// serving remote code from the loopback controller.
	clash.ExternalUI = ""
	clash.ExternalUIDownloadURL = ""
	clash.ExternalUIDownloadDetour = ""
	clash.AccessControlAllowPrivateNetwork = false
	clash.AccessControlAllowOrigin = nil

	// The selected-node and fake-ip state has to survive a restart, and the app
	// expects it under the working directory Init was given.
	if opts.Experimental.CacheFile == nil {
		opts.Experimental.CacheFile = &option.CacheFileOptions{}
	}
	opts.Experimental.CacheFile.Enabled = true
	if home := currentHomeDir(); home != "" {
		opts.Experimental.CacheFile.Path = filepath.Join(home, "singbox-cache.db")
	}

	// V2Ray's API listens on a real socket and needs a gRPC build tag we do not
	// ship, so it can only fail at construction time.
	opts.Experimental.V2RayAPI = nil

	// Log output must never reach stdout: the desktop host speaks NDJSON there.
	// An empty output routes through the platform writer plus stderr, which the
	// host already treats as a log channel.
	level := "info"
	if opts.Log != nil && opts.Log.Level != "" {
		level = opts.Log.Level
	}
	opts.Log = &option.LogOptions{Level: level}

	if opts.Route == nil {
		opts.Route = &option.RouteOptions{}
	}
	// Required for the Android protect() hook to be consulted at all, and it is
	// what desktop wants anyway.
	opts.Route.AutoDetectInterface = true

	applySingboxTunOverrides(opts, start)
}

// applySingboxTunOverrides makes the tun inbound match the interface the host is
// about to build, creating one if the config has none.
func applySingboxTunOverrides(opts *option.Options, start startOptions) {
	tun := findTunInbound(opts)
	if tun == nil {
		tun = &option.TunInboundOptions{}
		opts.Inbounds = append(opts.Inbounds, option.Inbound{
			Type:    sbconstant.TypeTun,
			Tag:     "tun-in",
			Options: tun,
		})
	}

	if len(tun.Address) == 0 {
		if prefix, err := netip.ParsePrefix(defaultSingboxTunAddress); err == nil {
			tun.Address = append(tun.Address, prefix)
		}
	}
	if start.TunMTU > 0 {
		tun.MTU = start.TunMTU
	}
	switch start.TunStack {
	case "gvisor", "system", "mixed":
		tun.Stack = start.TunStack
	}

	// A descriptor handed over by the host is already routed by the platform, so
	// the core must not try to install routes of its own.
	if start.TunMode == TunModeAuto {
		tun.AutoRoute = true
	} else {
		tun.AutoRoute = false
		tun.AutoRedirect = false
		tun.StrictRoute = false
	}

	// The host resolves through the TUN address, so hijacking is the only mode
	// that works; "disabled" would leave those queries unanswered.
	if tun.DNSMode == "" || tun.DNSMode == "disabled" {
		tun.DNSMode = "hijack"
	}
}

// findTunInbound returns the options of the first tun inbound, or nil.
func findTunInbound(opts *option.Options) *option.TunInboundOptions {
	for i := range opts.Inbounds {
		if opts.Inbounds[i].Type != sbconstant.TypeTun {
			continue
		}
		if tun, ok := opts.Inbounds[i].Options.(*option.TunInboundOptions); ok {
			return tun
		}
	}
	return nil
}

// singboxTunDNS reports the resolver address the host should advertise.
func singboxTunDNS(tun *option.TunInboundOptions) string {
	for _, addr := range tun.DNSAddress {
		if addr.Is4() {
			return addr.String()
		}
	}
	// sing-box itself defaults to the address right after the interface one.
	for _, prefix := range tun.Address {
		if !prefix.Addr().Is4() {
			continue
		}
		if next := prefix.Addr().Next(); next.IsValid() && prefix.Contains(next) {
			return next.String()
		}
		return prefix.Addr().String()
	}
	return ""
}

// singboxLogWriter forwards the core's log lines to the host delegate.
type singboxLogWriter struct{}

func (singboxLogWriter) WriteMessage(level sblog.Level, message string) {
	emitLog(singboxLogLevel(level), message)
}

// singboxLogLevel maps sing-box levels onto the four the host understands.
func singboxLogLevel(level sblog.Level) string {
	switch level {
	case sblog.LevelTrace, sblog.LevelDebug:
		return "debug"
	case sblog.LevelWarn:
		return "warning"
	case sblog.LevelError, sblog.LevelFatal, sblog.LevelPanic:
		return "error"
	default:
		return "info"
	}
}
