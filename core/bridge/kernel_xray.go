package bridge

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"sync"
	"time"

	C "github.com/metacubex/mihomo/constant"
	xlog "github.com/xtls/xray-core/common/log"
	"github.com/xtls/xray-core/common/platform"
	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	xserial "github.com/xtls/xray-core/infra/conf/serial"

	// Registers every inbound/outbound/transport handler, mirroring xray's own
	// entrypoint. Without it core.New rejects any config.
	_ "github.com/xtls/xray-core/main/distro/all"

	// distro/all does not reach the tun inbound; infra/conf/tun.go is the only
	// importer, so name it explicitly.
	_ "github.com/xtls/xray-core/proxy/tun"
)

// Tags used by the generated config. They are part of the contract with the host:
// traffic is summed over the outbound tags, so a hand-written config has to reuse
// them to report anything.
const (
	xrayTunTag    = "tun-in"
	xrayDirectTag = "direct"
	xrayBlockTag  = "block"
)

// xrayTunIPv4 mirrors MaomaoVpnService's fallback. xray's tun inbound has no
// addressing of its own: its gvisor stack runs promiscuous, so any /30 works.
const xrayTunIPv4 = "198.18.0.1/30"

// xrayStatTags are the outbounds whose counters add up to the tunnel's traffic.
// The blackhole outbound is left out because it discards everything it receives.
var xrayStatTags = []string{xrayDirectTag}

// xrayCore is the xray engine. The tun inbound reads its descriptor from the
// process environment, so only one instance can be up at a time.
var xrayCore = &xrayKernel{}

type xrayKernel struct {
	mu       sync.Mutex
	instance *xcore.Instance

	lastTotal   trafficStat
	lastSampled time.Time
}

func (k *xrayKernel) name() string { return KernelXray }

func (k *xrayKernel) version() string { return xcore.Version() }

func (k *xrayKernel) validateConfig(configPath string) error {
	raw, err := k.buildConfig(startOptions{ConfigPath: configPath})
	if err != nil {
		return err
	}
	_, err = xserial.LoadJSONConfig(bytes.NewReader(raw))
	return err
}

func (k *xrayKernel) tunOptions(configPath string) (tunOptions, error) {
	// No DNS server is advertised: xray's tun inbound does not hijack :53, so
	// pointing the system resolver into the tunnel would black-hole every query.
	return tunOptions{IPv4: xrayTunIPv4, MTU: defaultTunMTU}, nil
}

func (k *xrayKernel) start(opts startOptions) error {
	k.mu.Lock()
	defer k.mu.Unlock()

	if k.instance != nil {
		return errors.New("xray is already running")
	}

	raw, err := k.buildConfig(opts)
	if err != nil {
		return err
	}

	// The tun device is built while core.New creates the config objects, not in
	// Start, and it reads the descriptor from the environment. Both variables must
	// therefore be in place before that call.
	if err := os.Setenv(platform.TunFdKey, strconv.Itoa(opts.TunFd)); err != nil {
		return err
	}
	if err := os.Setenv(platform.AssetLocation, C.Path.HomeDir()); err != nil {
		return err
	}

	installXrayDialerHook()

	cfg, err := xserial.LoadJSONConfig(bytes.NewReader(raw))
	if err != nil {
		return err
	}
	instance, err := xcore.New(cfg)
	if err != nil {
		return err
	}
	// core.New installs xray's own log handler, and RegisterHandler discards the
	// previous one, so ours has to be registered afterwards.
	xlog.RegisterHandler(xrayLogHandler{})

	if err := instance.Start(); err != nil {
		_ = instance.Close()
		return err
	}

	k.instance = instance
	k.lastTotal = trafficStat{}
	k.lastSampled = time.Time{}
	return nil
}

// reload is unsupported: the tun inbound has no Close and registers no workers, so
// closing the instance leaves its gvisor stack attached to the descriptor. A second
// instance would race the first one for every packet.
func (k *xrayKernel) reload(opts startOptions) error {
	return errors.New("xray does not support reload")
}

func (k *xrayKernel) stop() {
	k.mu.Lock()
	instance := k.instance
	k.instance = nil
	k.lastTotal = trafficStat{}
	k.lastSampled = time.Time{}
	k.mu.Unlock()

	if instance == nil {
		return
	}
	// The host keeps ownership of the TUN descriptor; nothing in xray's close path
	// touches it.
	_ = instance.Close()
}

// controllerInfo is empty: xray only speaks gRPC, which is not exposed to the host.
func (k *xrayKernel) controllerInfo() controllerInfo { return controllerInfo{} }

// traffic derives a rate from the counter deltas between polls, because xray only
// exposes cumulative totals.
func (k *xrayKernel) traffic() trafficStat {
	total := k.trafficTotal()
	now := time.Now()

	k.mu.Lock()
	defer k.mu.Unlock()

	previous, sampledAt := k.lastTotal, k.lastSampled
	k.lastTotal, k.lastSampled = total, now

	if sampledAt.IsZero() {
		return trafficStat{}
	}
	elapsed := now.Sub(sampledAt).Seconds()
	if elapsed <= 0 {
		return trafficStat{}
	}
	return trafficStat{
		Up:   xrayRate(total.Up-previous.Up, elapsed),
		Down: xrayRate(total.Down-previous.Down, elapsed),
	}
}

func (k *xrayKernel) trafficTotal() trafficStat {
	manager := k.statsManager()
	if manager == nil {
		return trafficStat{}
	}

	var total trafficStat
	for _, tag := range xrayStatTags {
		total.Up += xrayCounterValue(manager, "outbound>>>"+tag+">>>traffic>>>uplink")
		total.Down += xrayCounterValue(manager, "outbound>>>"+tag+">>>traffic>>>downlink")
	}
	return total
}

func (k *xrayKernel) statsManager() stats.Manager {
	k.mu.Lock()
	instance := k.instance
	k.mu.Unlock()

	if instance == nil {
		return nil
	}
	manager, _ := instance.GetFeature(stats.ManagerType()).(stats.Manager)
	return manager
}

// buildConfig turns the host's config path into an xray JSON config.
func (k *xrayKernel) buildConfig(opts startOptions) ([]byte, error) {
	if opts.ConfigPath == "" {
		return nil, errors.New("configPath is empty")
	}
	body, err := os.ReadFile(opts.ConfigPath)
	if err != nil {
		return nil, err
	}
	// A JSON body is taken as a complete xray config. mihomo's YAML carries proxy
	// groups xray cannot express, so for now it only contributes the tunnel and the
	// generated skeleton routes everything directly.
	if bytes.HasPrefix(bytes.TrimSpace(body), []byte("{")) {
		return body, nil
	}

	mtu := opts.TunMTU
	if mtu == 0 {
		mtu = defaultTunMTU
	}
	tunSettings, err := json.Marshal(xrayTunSettings{Name: xrayTunName(), MTU: mtu})
	if err != nil {
		return nil, err
	}

	// Fragmenting is currently only reachable on the direct outbound, because the
	// skeleton has no node outbounds yet.
	direct := xrayOutbound{Tag: xrayDirectTag, Protocol: "freedom"}
	if opts.XrayFragment {
		settings, err := json.Marshal(xrayFreedomSettings{Fragment: defaultXrayFragment()})
		if err != nil {
			return nil, err
		}
		direct.Settings = settings
	}

	return json.Marshal(xrayDocument{
		Log: xrayLogSettings{Access: "none", Error: "none", LogLevel: "warning"},
		Policy: xrayPolicySettings{System: xraySystemPolicy{
			StatsOutboundUplink:   true,
			StatsOutboundDownlink: true,
		}},
		Inbounds: []xrayInbound{{
			Tag:      xrayTunTag,
			Protocol: "tun",
			Settings: tunSettings,
			Sniffing: &xraySniffing{Enabled: true, DestOverride: []string{"http", "tls"}},
		}},
		Outbounds: []xrayOutbound{
			direct,
			{Tag: xrayBlockTag, Protocol: "blackhole"},
		},
	})
}

// xrayTunName names the tunnel device. darwin opens its own utun when no descriptor
// is handed over, and only accepts a utunN name for that.
func xrayTunName() string {
	if runtime.GOOS == "darwin" {
		return "utun9"
	}
	return "xray0"
}

func xrayRate(delta int64, seconds float64) int64 {
	if delta <= 0 {
		return 0
	}
	return int64(float64(delta) / seconds)
}

func xrayCounterValue(manager stats.Manager, name string) int64 {
	counter := manager.GetCounter(name)
	if counter == nil {
		return 0
	}
	return counter.Value()
}

// xrayLogHandler forwards xray's log bus to the host delegate. It replaces xray's
// own handler, so the severity filtering that app/log would have done happens here.
type xrayLogHandler struct{}

func (xrayLogHandler) Handle(msg xlog.Message) {
	mu.Lock()
	d := delegate
	mu.Unlock()
	if d == nil {
		return
	}

	level, payload := xrayLogEvent(msg)
	if level == "" {
		return
	}
	d.OnLog(level, payload)
}

// xrayLogEvent maps a message to the bridge's level names. An empty level drops it.
func xrayLogEvent(msg xlog.Message) (string, string) {
	general, ok := msg.(*xlog.GeneralMessage)
	if !ok {
		return "info", msg.String()
	}
	switch general.Severity {
	case xlog.Severity_Error:
		return "error", fmt.Sprint(general.Content)
	case xlog.Severity_Warning:
		return "warning", fmt.Sprint(general.Content)
	case xlog.Severity_Debug:
		// Dropped so the volume stays close to mihomo's default level.
		return "", ""
	default:
		return "info", fmt.Sprint(general.Content)
	}
}

type xrayDocument struct {
	Log       xrayLogSettings    `json:"log"`
	Stats     struct{}           `json:"stats"`
	Policy    xrayPolicySettings `json:"policy"`
	Inbounds  []xrayInbound      `json:"inbounds"`
	Outbounds []xrayOutbound     `json:"outbounds"`
}

type xrayLogSettings struct {
	Access   string `json:"access"`
	Error    string `json:"error"`
	LogLevel string `json:"loglevel"`
}

type xrayPolicySettings struct {
	System xraySystemPolicy `json:"system"`
}

type xraySystemPolicy struct {
	StatsOutboundUplink   bool `json:"statsOutboundUplink"`
	StatsOutboundDownlink bool `json:"statsOutboundDownlink"`
}

type xrayInbound struct {
	Tag      string          `json:"tag"`
	Protocol string          `json:"protocol"`
	Settings json.RawMessage `json:"settings,omitempty"`
	Sniffing *xraySniffing   `json:"sniffing,omitempty"`
}

type xraySniffing struct {
	Enabled      bool     `json:"enabled"`
	DestOverride []string `json:"destOverride"`
}

type xrayOutbound struct {
	Tag            string          `json:"tag"`
	Protocol       string          `json:"protocol"`
	Settings       json.RawMessage `json:"settings,omitempty"`
	StreamSettings json.RawMessage `json:"streamSettings,omitempty"`
}

type xrayTunSettings struct {
	Name string `json:"name"`
	MTU  uint32 `json:"MTU"`
}

type xrayFreedomSettings struct {
	Fragment *xrayFragmentSettings `json:"fragment,omitempty"`
}

// Length and Interval must be present and LengthMin must be non-zero, xray
// rejects the config otherwise.
type xrayFragmentSettings struct {
	Packets  string `json:"packets"`
	Length   string `json:"length"`
	Interval string `json:"interval"`
}

func defaultXrayFragment() *xrayFragmentSettings {
	return &xrayFragmentSettings{Packets: "tlshello", Length: "100-200", Interval: "10-20"}
}
