package bridge

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const singboxTestConfig = `
proxies:
  - name: node-a
    type: ss
    server: a.example.com
    port: "8388"
    cipher: aes-128-gcm
    password: secret
    udp: true
  - name: node-a
    type: trojan
    server: b.example.com
    port: "443"
    password: secret
    sni: b.example.com
  - name: unsupported
    type: ssr
    server: c.example.com
    port: "1234"
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Auto
      - node-a
      - DIRECT
  - name: Auto
    type: url-test
    proxies:
      - node-a
  - name: Empty
    type: select
    proxies:
      - missing-node
rules:
  - GEOIP,CN,DIRECT
`

// singboxConfigOf converts and unmarshals so assertions can inspect the result.
func singboxConfigOf(t *testing.T, yamlText string) (string, map[string]any) {
	t.Helper()
	raw, err := ConvertToSingbox(yamlText)
	if err != nil {
		t.Fatalf("ConvertToSingbox: %v", err)
	}
	var doc map[string]any
	if err := json.Unmarshal([]byte(raw), &doc); err != nil {
		t.Fatalf("generated config is not valid json: %v", err)
	}
	return raw, doc
}

func outboundsByTag(t *testing.T, doc map[string]any) map[string]map[string]any {
	t.Helper()
	list, ok := doc["outbounds"].([]any)
	if !ok {
		t.Fatalf("outbounds is not a list: %#v", doc["outbounds"])
	}
	byTag := make(map[string]map[string]any, len(list))
	for _, entry := range list {
		out, ok := entry.(map[string]any)
		if !ok {
			t.Fatalf("outbound is not an object: %#v", entry)
		}
		tag, _ := out["tag"].(string)
		if _, exists := byTag[tag]; exists {
			t.Fatalf("duplicate outbound tag %q, sing-box rejects those", tag)
		}
		byTag[tag] = out
	}
	return byTag
}

func stringsOf(t *testing.T, value any) []string {
	t.Helper()
	list, ok := value.([]any)
	if !ok {
		t.Fatalf("not a list: %#v", value)
	}
	out := make([]string, 0, len(list))
	for _, entry := range list {
		text, ok := entry.(string)
		if !ok {
			t.Fatalf("not a string: %#v", entry)
		}
		out = append(out, text)
	}
	return out
}

func TestConvertToSingboxProducesLoadableConfig(t *testing.T) {
	raw, _ := singboxConfigOf(t, singboxTestConfig)

	path := filepath.Join(t.TempDir(), "runtime.json")
	if err := os.WriteFile(path, []byte(raw), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	// validate builds a real instance, so it catches everything the JSON schema
	// alone would not: removed options, unknown outbound references and groups
	// with no members.
	engine := &singboxEngine{}
	if err := engine.validate(path); err != nil {
		t.Fatalf("generated config was rejected by sing-box: %v\n%s", err, raw)
	}
}

func TestConvertToSingboxDeduplicatesProxyTags(t *testing.T) {
	_, doc := singboxConfigOf(t, singboxTestConfig)
	byTag := outboundsByTag(t, doc)

	if _, ok := byTag["node-a"]; !ok {
		t.Error("first node-a kept its name, expected it in outbounds")
	}
	if _, ok := byTag["node-a-2"]; !ok {
		t.Errorf("second node-a was not renamed, got tags %v", byTag)
	}
}

func TestConvertToSingboxSynthesizesProxyGroups(t *testing.T) {
	_, doc := singboxConfigOf(t, singboxTestConfig)
	byTag := outboundsByTag(t, doc)

	proxy, ok := byTag["Proxy"]
	if !ok {
		t.Fatalf("select group was dropped, got tags %v", byTag)
	}
	if proxy["type"] != "selector" {
		t.Errorf("Proxy type = %#v, want selector", proxy["type"])
	}
	if got := stringsOf(t, proxy["outbounds"]); strings.Join(got, ",") != "Auto,node-a,direct" {
		t.Errorf("Proxy outbounds = %v, want the resolved members in order", got)
	}

	auto, ok := byTag["Auto"]
	if !ok {
		t.Fatalf("url-test group was dropped, got tags %v", byTag)
	}
	if auto["type"] != "urltest" {
		t.Errorf("Auto type = %#v, want urltest", auto["type"])
	}

	// A group whose members do not exist would abort startup with "missing tags".
	if _, ok := byTag["Empty"]; ok {
		t.Error("group with no usable member was kept, expected it to be skipped")
	}
}

func TestConvertToSingboxKeepsGeneratedEntrypoints(t *testing.T) {
	_, doc := singboxConfigOf(t, singboxTestConfig)
	byTag := outboundsByTag(t, doc)

	for _, tag := range [...]string{"select", "urltest", "direct", "block"} {
		if _, ok := byTag[tag]; !ok {
			t.Errorf("generated outbound %q is missing", tag)
		}
	}
	if got := stringsOf(t, byTag["select"]["outbounds"]); got[0] != "urltest" {
		t.Errorf("select outbounds = %v, want urltest first", got)
	}

	route, ok := doc["route"].(map[string]any)
	if !ok {
		t.Fatalf("route is not an object: %#v", doc["route"])
	}
	if route["final"] != "select" {
		t.Errorf("route.final = %#v, want select", route["final"])
	}
	if route["auto_detect_interface"] != true {
		t.Errorf("route.auto_detect_interface = %#v, want true", route["auto_detect_interface"])
	}
}

func TestConvertToSingboxRejectsConfigWithoutProxies(t *testing.T) {
	if _, err := ConvertToSingbox("mode: rule\n"); err == nil {
		t.Error("expected an error for a config with no proxies")
	}
	if _, err := ConvertToSingbox("   \n"); err == nil {
		t.Error("expected an error for an empty config")
	}
}

// sing-box refuses a detour that lands on a direct outbound carrying no dialer
// options, and it only says so once the DNS transport starts. validate stops at
// box.New, so nothing else in this file would notice.
func TestConvertToSingboxKeepsDNSOffOptionlessDirectDetour(t *testing.T) {
	_, doc := singboxConfigOf(t, singboxTestConfig)

	optionless := make(map[string]bool)
	for tag, out := range outboundsByTag(t, doc) {
		// Every dialer option is a top-level key, so a direct outbound with
		// nothing besides its type and tag is the shape sing-box rejects.
		if out["type"] == "direct" && len(out) == 2 {
			optionless[tag] = true
		}
	}

	dns, ok := doc["dns"].(map[string]any)
	if !ok {
		t.Fatalf("dns is not an object: %#v", doc["dns"])
	}
	servers, ok := dns["servers"].([]any)
	if !ok {
		t.Fatalf("dns.servers is not a list: %#v", dns["servers"])
	}
	for _, entry := range servers {
		server, ok := entry.(map[string]any)
		if !ok {
			t.Fatalf("dns server is not an object: %#v", entry)
		}
		if detour, _ := server["detour"].(string); optionless[detour] {
			t.Errorf(
				"dns server %#v detours to %q, which has no dialer options",
				server["tag"], detour,
			)
		}
	}
}
