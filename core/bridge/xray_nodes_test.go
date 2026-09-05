package bridge

import (
	"encoding/json"
	"testing"
)

func extractTestNodes(t *testing.T, configYAML string) []xrayNode {
	t.Helper()

	raw, err := ExtractNodes(configYAML)
	if err != nil {
		t.Fatalf("ExtractNodes: %v", err)
	}
	var list xrayNodeList
	if err := json.Unmarshal([]byte(raw), &list); err != nil {
		t.Fatalf("unmarshal nodes: %v", err)
	}
	return list.Nodes
}

func TestExtractNodesMapsSupportedProtocols(t *testing.T) {
	nodes := extractTestNodes(t, `
proxies:
  - name: vless-ws
    type: vless
    server: a.example.com
    port: 443
    uuid: 0f6f6bb9-6cbb-4f2f-9a35-2f2a1c8d3c1e
    tls: true
    network: ws
    servername: a.example.com
    client-fingerprint: chrome
    ws-opts:
      path: /ws
      headers:
        Host: cdn.example.com
        User-Agent: probe
  - name: vless-reality
    type: vless
    server: b.example.com
    port: 8443
    uuid: 6e1f4c2a-0c4e-4a1f-8f2f-9a35b7c1d2e3
    flow: xtls-rprx-vision
    tls: true
    servername: www.microsoft.com
    reality-opts:
      public-key: 6PLR9jKPvVaBQfBRcNQ0Bt4V7gGXPcKh_1yYMxCn9lA
      short-id: 0123abcd
  - name: vmess-tcp
    type: vmess
    server: c.example.com
    port: 80
    uuid: 3d2f8a1b-5c6d-4e7f-8091-a2b3c4d5e6f7
    alterId: 0
    cipher: auto
  - name: trojan-grpc
    type: trojan
    server: d.example.com
    port: 443
    password: secret
    network: grpc
    sni: d.example.com
    grpc-opts:
      grpc-service-name: tunnel
  - name: ss-aead
    type: ss
    server: e.example.com
    port: 8388
    cipher: aes-256-gcm
    password: pass
    udp: true
  - name: socks-plain
    type: socks5
    server: f.example.com
    port: 1080
    username: u
    password: p
  - name: http-plain
    type: http
    server: g.example.com
    port: 8080
`)

	if len(nodes) != 7 {
		t.Fatalf("expected 7 nodes, got %d", len(nodes))
	}

	protocols := map[string]string{
		"vless-ws":      "vless",
		"vless-reality": "vless",
		"vmess-tcp":     "vmess",
		"trojan-grpc":   "trojan",
		"ss-aead":       "shadowsocks",
		"socks-plain":   "socks",
		"http-plain":    "http",
	}
	for _, node := range nodes {
		if !node.Supported {
			t.Fatalf("node %q unsupported: %s", node.Name, node.Reason)
		}
		if node.Outbound == nil {
			t.Fatalf("node %q has no outbound", node.Name)
		}
		if node.Outbound.Tag != node.Tag {
			t.Fatalf("node %q tag mismatch: %q vs %q", node.Name, node.Outbound.Tag, node.Tag)
		}
		if want := protocols[node.Name]; node.Outbound.Protocol != want {
			t.Fatalf("node %q protocol = %q, want %q", node.Name, node.Outbound.Protocol, want)
		}
	}

	ws := nodes[0]
	if ws.Server != "a.example.com" || ws.Port != 443 {
		t.Fatalf("unexpected endpoint: %s:%d", ws.Server, ws.Port)
	}
	var wsStream xrayStreamSettings
	if err := json.Unmarshal(ws.Outbound.StreamSettings, &wsStream); err != nil {
		t.Fatalf("unmarshal stream: %v", err)
	}
	if wsStream.Network != "ws" || wsStream.Security != "tls" {
		t.Fatalf("unexpected ws stream: %+v", wsStream)
	}
	if wsStream.WSSettings == nil || wsStream.WSSettings.Path != "/ws" {
		t.Fatalf("unexpected ws settings: %+v", wsStream.WSSettings)
	}
	if wsStream.WSSettings.Host != "cdn.example.com" {
		t.Fatalf("ws host not lifted from headers: %+v", wsStream.WSSettings)
	}
	if _, ok := wsStream.WSSettings.Headers["Host"]; ok {
		t.Fatalf("host header should be removed: %+v", wsStream.WSSettings.Headers)
	}

	var vlessSettings xrayVlessSettings
	if err := json.Unmarshal(ws.Outbound.Settings, &vlessSettings); err != nil {
		t.Fatalf("unmarshal settings: %v", err)
	}
	if vlessSettings.Encryption != "none" {
		t.Fatalf("vless encryption = %q, want none", vlessSettings.Encryption)
	}

	var realityStream xrayStreamSettings
	if err := json.Unmarshal(nodes[1].Outbound.StreamSettings, &realityStream); err != nil {
		t.Fatalf("unmarshal reality stream: %v", err)
	}
	if realityStream.Security != "reality" || realityStream.Network != "tcp" {
		t.Fatalf("unexpected reality stream: %+v", realityStream)
	}
	if realityStream.RealitySettings == nil || realityStream.RealitySettings.ShortID != "0123abcd" {
		t.Fatalf("unexpected reality settings: %+v", realityStream.RealitySettings)
	}
	if realityStream.TLSSettings != nil {
		t.Fatal("reality must not emit tlsSettings")
	}

	var grpcStream xrayStreamSettings
	if err := json.Unmarshal(nodes[3].Outbound.StreamSettings, &grpcStream); err != nil {
		t.Fatalf("unmarshal grpc stream: %v", err)
	}
	if grpcStream.Network != "grpc" || grpcStream.Security != "tls" {
		t.Fatalf("trojan must default to tls over grpc: %+v", grpcStream)
	}
	if grpcStream.GRPCSettings == nil || grpcStream.GRPCSettings.ServiceName != "tunnel" {
		t.Fatalf("unexpected grpc settings: %+v", grpcStream.GRPCSettings)
	}
}

func TestExtractNodesFlagsUnsupportedWithoutDropping(t *testing.T) {
	nodes := extractTestNodes(t, `
proxies:
  - name: hy2
    type: hysteria2
    server: a.example.com
    port: 443
    password: pass
  - name: tuic-node
    type: tuic
    server: b.example.com
    port: 443
  - name: ss-2022
    type: ss
    server: c.example.com
    port: 8388
    cipher: 2022-blake3-aes-128-gcm
    password: pass
  - name: ss-plugin
    type: ss
    server: d.example.com
    port: 8388
    cipher: aes-128-gcm
    password: pass
    plugin: obfs
  - name: vmess-h2
    type: vmess
    server: e.example.com
    port: 443
    uuid: 3d2f8a1b-5c6d-4e7f-8091-a2b3c4d5e6f7
    tls: true
    network: h2
  - name: vless-bad-flow
    type: vless
    server: f.example.com
    port: 443
    uuid: 0f6f6bb9-6cbb-4f2f-9a35-2f2a1c8d3c1e
    flow: xtls-rprx-direct
  - name: vless-bad-reality
    type: vless
    server: g.example.com
    port: 443
    uuid: 0f6f6bb9-6cbb-4f2f-9a35-2f2a1c8d3c1e
    reality-opts:
      public-key: not-a-key
  - name: vless-reality-ws
    type: vless
    server: h.example.com
    port: 443
    uuid: 0f6f6bb9-6cbb-4f2f-9a35-2f2a1c8d3c1e
    network: ws
    reality-opts:
      public-key: 6PLR9jKPvVaBQfBRcNQ0Bt4V7gGXPcKh_1yYMxCn9lA
`)

	if len(nodes) != 8 {
		t.Fatalf("expected 8 nodes, got %d", len(nodes))
	}
	for _, node := range nodes {
		if node.Supported {
			t.Fatalf("node %q should be unsupported", node.Name)
		}
		if node.Reason == "" {
			t.Fatalf("node %q needs a reason", node.Name)
		}
		if node.Outbound != nil {
			t.Fatalf("node %q should not carry an outbound", node.Name)
		}
		if node.Name == "" || node.Type == "" {
			t.Fatalf("unsupported node must keep its identity: %+v", node)
		}
	}
}

func TestExtractNodesDeduplicatesTags(t *testing.T) {
	nodes := extractTestNodes(t, `
proxies:
  - name: same
    type: ss
    server: a.example.com
    port: 8388
    cipher: aes-128-gcm
    password: pass
  - name: same
    type: ss
    server: b.example.com
    port: 8388
    cipher: aes-128-gcm
    password: pass
  - type: ss
    server: c.example.com
    port: 8388
    cipher: aes-128-gcm
    password: pass
`)

	if len(nodes) != 3 {
		t.Fatalf("expected 3 nodes, got %d", len(nodes))
	}
	if nodes[0].Tag != "same" || nodes[1].Tag != "same #2" {
		t.Fatalf("tags not deduplicated: %q, %q", nodes[0].Tag, nodes[1].Tag)
	}
	if nodes[2].Tag != "node-3" {
		t.Fatalf("unnamed node tag = %q, want node-3", nodes[2].Tag)
	}
}

func TestExtractNodesHandlesEmptyAndInvalidInput(t *testing.T) {
	if _, err := ExtractNodes("   "); err == nil {
		t.Fatal("expected error for empty config")
	}
	if _, err := ExtractNodes("proxies: [oops"); err == nil {
		t.Fatal("expected error for malformed yaml")
	}
	nodes := extractTestNodes(t, "proxies: []\n")
	if len(nodes) != 0 {
		t.Fatalf("expected no nodes, got %d", len(nodes))
	}
}

func TestExtractNodesMapsHTTPObfuscationToRaw(t *testing.T) {
	nodes := extractTestNodes(t, `
proxies:
  - name: vmess-obfs
    type: vmess
    server: a.example.com
    port: 80
    uuid: 3d2f8a1b-5c6d-4e7f-8091-a2b3c4d5e6f7
    network: http
    http-opts:
      method: GET
      path:
        - /video
      headers:
        Host:
          - cdn.example.com
`)

	if len(nodes) != 1 || !nodes[0].Supported {
		t.Fatalf("unexpected nodes: %+v", nodes)
	}
	var stream xrayStreamSettings
	if err := json.Unmarshal(nodes[0].Outbound.StreamSettings, &stream); err != nil {
		t.Fatalf("unmarshal stream: %v", err)
	}
	if stream.Network != "tcp" {
		t.Fatalf("clash network=http must map to tcp, got %q", stream.Network)
	}
	if stream.RAWSettings == nil || stream.RAWSettings.Header == nil {
		t.Fatalf("expected raw http header: %+v", stream.RAWSettings)
	}
	if stream.RAWSettings.Header.Type != "http" {
		t.Fatalf("unexpected header type: %q", stream.RAWSettings.Header.Type)
	}
	request := stream.RAWSettings.Header.Request
	if request == nil || request.Method != "GET" || len(request.Path) != 1 || request.Path[0] != "/video" {
		t.Fatalf("unexpected header request: %+v", request)
	}
	if got := request.Headers["Host"]; len(got) != 1 || got[0] != "cdn.example.com" {
		t.Fatalf("unexpected header host: %+v", request.Headers)
	}
}
