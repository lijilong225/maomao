package bridge

import (
	"strings"
	"testing"

	"github.com/metacubex/mihomo/common/yaml"
)

func TestMergeConfigDeepMergesMappings(t *testing.T) {
	base := "dns:\n  enable: false\n  nameserver:\n    - 1.1.1.1\nmode: rule\n"
	patch := "dns:\n  enable: true\nlog-level: debug\n"

	merged, err := MergeConfig(base, patch)
	if err != nil {
		t.Fatalf("MergeConfig: %v", err)
	}

	var got map[string]any
	if err := yaml.Unmarshal([]byte(merged), &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	dns, ok := asMapping(got["dns"])
	if !ok {
		t.Fatalf("dns is not a mapping: %#v", got["dns"])
	}
	if dns["enable"] != true {
		t.Errorf("dns.enable = %#v, want true", dns["enable"])
	}
	if _, ok := dns["nameserver"]; !ok {
		t.Error("dns.nameserver was dropped, expected it to survive the merge")
	}
	if got["mode"] != "rule" {
		t.Errorf("mode = %#v, want rule", got["mode"])
	}
	if got["log-level"] != "debug" {
		t.Errorf("log-level = %#v, want debug", got["log-level"])
	}
}

func TestMergeConfigNullDeletesKey(t *testing.T) {
	merged, err := MergeConfig("secret: keep\nport: 7890\n", "port: ~\n")
	if err != nil {
		t.Fatalf("MergeConfig: %v", err)
	}

	var got map[string]any
	if err := yaml.Unmarshal([]byte(merged), &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if _, ok := got["port"]; ok {
		t.Error("port should have been deleted by an explicit null")
	}
	if got["secret"] != "keep" {
		t.Errorf("secret = %#v, want keep", got["secret"])
	}
}

func TestMergeConfigReplacesLists(t *testing.T) {
	merged, err := MergeConfig("rules:\n  - MATCH,DIRECT\n", "rules:\n  - MATCH,Proxy\n")
	if err != nil {
		t.Fatalf("MergeConfig: %v", err)
	}
	if strings.Contains(merged, "DIRECT") {
		t.Errorf("lists must be replaced, not appended: %s", merged)
	}
}

func TestMergeConfigRejectsInvalidPatch(t *testing.T) {
	if _, err := MergeConfig("mode: rule\n", "\tnot: yaml\n"); err == nil {
		t.Error("expected an error for a malformed patch")
	}
}

func TestConvertSubscriptionPassesThroughYAML(t *testing.T) {
	config := "proxies:\n  - name: a\n    type: socks5\n    server: example.com\n    port: 1080\n"

	got, err := ConvertSubscription(config)
	if err != nil {
		t.Fatalf("ConvertSubscription: %v", err)
	}
	if got != strings.TrimSpace(config) {
		t.Errorf("a mihomo config must be returned verbatim, got:\n%s", got)
	}
}

func TestConvertSubscriptionParsesShareLinks(t *testing.T) {
	links := "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@example.com:8388#node-a\n" +
		"trojan://secret@example.org:443#node-b\n"

	got, err := ConvertSubscription(links)
	if err != nil {
		t.Fatalf("ConvertSubscription: %v", err)
	}

	var doc map[string]any
	if err := yaml.Unmarshal([]byte(got), &doc); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	proxies, ok := doc["proxies"].([]any)
	if !ok {
		t.Fatalf("proxies is not a list: %#v", doc["proxies"])
	}
	if len(proxies) != 2 {
		t.Errorf("got %d proxies, want 2", len(proxies))
	}
}

func TestConvertSubscriptionRejectsEmptyBody(t *testing.T) {
	if _, err := ConvertSubscription("   \n"); err == nil {
		t.Error("expected an error for an empty subscription")
	}
}

func TestConvertSubscriptionRejectsUnusableBody(t *testing.T) {
	if _, err := ConvertSubscription("this is not a subscription"); err == nil {
		t.Error("expected an error for a body with no proxies")
	}
}
