package bridge

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/common/yaml"
	C "github.com/metacubex/mihomo/constant"
)

// Defaults applied to the fields a probe request leaves unset.
const (
	defaultProbeURL         = "https://www.gstatic.com/generate_204"
	defaultProbeTimeout     = 5 * time.Second
	defaultProbeConcurrency = 8
)

// probeRequest is the JSON payload accepted by ProbeDelay.
type probeRequest struct {
	// ConfigYAML is a mihomo config; only its proxies section is read.
	ConfigYAML string `json:"configYaml"`
	// ProviderBodies are cached proxy-provider payloads keyed by provider name,
	// so nodes that live outside the config itself can be probed too.
	ProviderBodies map[string]string `json:"providerBodies"`
	// Names restricts the probe to those nodes; empty means every node found.
	Names       []string `json:"names"`
	URL         string   `json:"url"`
	TimeoutMs   int      `json:"timeoutMs"`
	Concurrency int      `json:"concurrency"`
}

// probeReply reports milliseconds per node name, 0 for a node that answered
// nothing. A node the core could not build at all is absent instead, so the
// host can tell an unsupported protocol apart from an unreachable server.
type probeReply struct {
	Delays map[string]int `json:"delays"`
}

// proxiesSection is the only part of a config or provider body a probe needs.
type proxiesSection struct {
	Proxies []map[string]any `yaml:"proxies"`
}

// ProbeDelay measures how long each node takes to fetch the test URL through
// itself, the same measurement the running core exposes as /proxies/{name}/delay.
//
// Every node is built as a standalone outbound and dialled directly, so no
// tunnel, controller or VPN permission is involved and nothing outlives the
// call. Takes a probeRequest and returns a probeReply, both as JSON.
func ProbeDelay(requestJSON string) (string, error) {
	var req probeRequest
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return "", fmt.Errorf("invalid probe request: %w", err)
	}

	proxies, err := buildProbeProxies(req)
	if err != nil {
		return "", err
	}
	defer func() {
		for _, proxy := range proxies {
			_ = proxy.Close()
		}
	}()

	buf, err := json.Marshal(probeReply{Delays: runProbe(proxies, req)})
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

func buildProbeProxies(req probeRequest) ([]C.Proxy, error) {
	wanted := make(map[string]struct{}, len(req.Names))
	for _, name := range req.Names {
		wanted[name] = struct{}{}
	}

	providers := make([]string, 0, len(req.ProviderBodies))
	for name := range req.ProviderBodies {
		providers = append(providers, name)
	}
	// Only affects which body wins a duplicate node name, but keeps it stable.
	sort.Strings(providers)

	bodies := make([]string, 0, 1+len(providers))
	bodies = append(bodies, req.ConfigYAML)
	for _, name := range providers {
		bodies = append(bodies, req.ProviderBodies[name])
	}

	seen := make(map[string]struct{})
	var proxies []C.Proxy
	for _, body := range bodies {
		mappings, err := decodeProxiesSection(body)
		if err != nil {
			return nil, fmt.Errorf("cannot read proxies: %w", err)
		}
		for _, mapping := range mappings {
			name, _ := mapping["name"].(string)
			if name == "" {
				continue
			}
			if len(wanted) > 0 {
				if _, ok := wanted[name]; !ok {
					continue
				}
			}
			if _, ok := seen[name]; ok {
				continue
			}
			seen[name] = struct{}{}
			proxy, err := adapter.ParseProxy(mapping)
			if err != nil {
				continue
			}
			proxies = append(proxies, proxy)
		}
	}
	return proxies, nil
}

func decodeProxiesSection(body string) ([]map[string]any, error) {
	if strings.TrimSpace(body) == "" {
		return nil, nil
	}
	var section proxiesSection
	if err := yaml.Unmarshal([]byte(body), &section); err != nil {
		return nil, err
	}
	return section.Proxies, nil
}

func runProbe(proxies []C.Proxy, req probeRequest) map[string]int {
	delays := make(map[string]int, len(proxies))
	if len(proxies) == 0 {
		return delays
	}

	url := req.URL
	if url == "" {
		url = defaultProbeURL
	}
	timeout := defaultProbeTimeout
	if req.TimeoutMs > 0 {
		timeout = time.Duration(req.TimeoutMs) * time.Millisecond
	}
	workers := req.Concurrency
	if workers <= 0 {
		workers = defaultProbeConcurrency
	}
	if workers > len(proxies) {
		workers = len(proxies)
	}

	var (
		results sync.Mutex
		wg      sync.WaitGroup
	)
	queue := make(chan C.Proxy)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for proxy := range queue {
				ctx, cancel := context.WithTimeout(context.Background(), timeout)
				delay, err := proxy.URLTest(ctx, url, nil)
				cancel()
				measured := int(delay)
				switch {
				case err != nil:
					measured = 0
				case measured == 0:
					// The core truncates to whole milliseconds, so keep a
					// sub-millisecond success out of the failure bucket.
					measured = 1
				}
				results.Lock()
				delays[proxy.Name()] = measured
				results.Unlock()
			}
		}()
	}
	for _, proxy := range proxies {
		queue <- proxy
	}
	close(queue)
	wg.Wait()
	return delays
}
