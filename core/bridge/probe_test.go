package bridge

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestProbeDelayMeasuresDirectAgainstLocalServer(t *testing.T) {
	server := httptest.NewServer(
		http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusNoContent)
		}),
	)
	defer server.Close()

	request, err := json.Marshal(probeRequest{
		ConfigYAML: "proxies:\n  - name: local\n    type: direct\n",
		URL:        server.URL,
		TimeoutMs:  3000,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	delays := probeForTest(t, string(request))
	delay, ok := delays["local"]
	if !ok {
		t.Fatalf("local is missing from %#v", delays)
	}
	if delay <= 0 {
		t.Errorf("delay = %d, want a positive measurement", delay)
	}
}

func TestProbeDelayReportsZeroForAnUnreachableServer(t *testing.T) {
	// Reserved for documentation, so nothing can be listening on it.
	config := "proxies:\n" +
		"  - name: dead\n" +
		"    type: socks5\n" +
		"    server: 203.0.113.1\n" +
		"    port: 1080\n"
	request, err := json.Marshal(probeRequest{
		ConfigYAML: config,
		URL:        "http://203.0.113.1/generate_204",
		TimeoutMs:  500,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	delays := probeForTest(t, string(request))
	delay, ok := delays["dead"]
	if !ok {
		t.Fatalf("dead is missing from %#v", delays)
	}
	if delay != 0 {
		t.Errorf("delay = %d, want 0", delay)
	}
}

func TestProbeDelaySkipsNodesOutsideNames(t *testing.T) {
	config := "proxies:\n" +
		"  - name: wanted\n    type: direct\n" +
		"  - name: ignored\n    type: direct\n"
	request, err := json.Marshal(probeRequest{
		ConfigYAML: config,
		Names:      []string{"wanted"},
		URL:        "http://127.0.0.1:1/",
		TimeoutMs:  200,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	delays := probeForTest(t, string(request))
	if _, ok := delays["wanted"]; !ok {
		t.Errorf("wanted is missing from %#v", delays)
	}
	if _, ok := delays["ignored"]; ok {
		t.Errorf("ignored was probed, got %#v", delays)
	}
}

func TestProbeDelayOmitsUnparsableNodes(t *testing.T) {
	config := "proxies:\n  - name: mystery\n    type: not-a-protocol\n"
	request, err := json.Marshal(probeRequest{
		ConfigYAML: config,
		URL:        "http://127.0.0.1:1/",
		TimeoutMs:  200,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	delays := probeForTest(t, string(request))
	if _, ok := delays["mystery"]; ok {
		t.Errorf("mystery was reported, got %#v", delays)
	}
}

func TestProbeDelayReadsProviderBodies(t *testing.T) {
	request, err := json.Marshal(probeRequest{
		ConfigYAML: "proxies: []\n",
		ProviderBodies: map[string]string{
			"remote": "proxies:\n  - name: from-provider\n    type: direct\n",
		},
		URL:       "http://127.0.0.1:1/",
		TimeoutMs: 200,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	delays := probeForTest(t, string(request))
	if _, ok := delays["from-provider"]; !ok {
		t.Errorf("from-provider is missing from %#v", delays)
	}
}

func TestProbeDelayRejectsMalformedRequests(t *testing.T) {
	if _, err := ProbeDelay("not json"); err == nil {
		t.Error("ProbeDelay accepted a malformed request")
	}
}

func probeForTest(t *testing.T, request string) map[string]int {
	t.Helper()
	raw, err := ProbeDelay(request)
	if err != nil {
		t.Fatalf("ProbeDelay: %v", err)
	}
	var reply probeReply
	if err := json.Unmarshal([]byte(raw), &reply); err != nil {
		t.Fatalf("unmarshal reply %s: %v", raw, err)
	}
	if reply.Delays == nil {
		t.Fatalf("reply has no delays: %s", raw)
	}
	return reply.Delays
}
