package bridge

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	xserial "github.com/xtls/xray-core/infra/conf/serial"
)

func TestXrayBuildConfigIsLoadable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "source.yaml")
	if err := os.WriteFile(path, []byte("proxies: []\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	raw, err := xrayCore.buildConfig(startOptions{ConfigPath: path, TunFd: 7, TunMTU: 1500})
	if err != nil {
		t.Fatalf("buildConfig: %v", err)
	}
	if _, err := xserial.LoadJSONConfig(bytes.NewReader(raw)); err != nil {
		t.Fatalf("generated config rejected by xray: %v\n%s", err, raw)
	}
}

func TestXrayBuildConfigPassesThroughJSON(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	body := []byte(`{"outbounds":[{"protocol":"freedom"}]}`)
	if err := os.WriteFile(path, body, 0o600); err != nil {
		t.Fatal(err)
	}

	raw, err := xrayCore.buildConfig(startOptions{ConfigPath: path})
	if err != nil {
		t.Fatalf("buildConfig: %v", err)
	}
	if !bytes.Equal(raw, body) {
		t.Fatalf("json config was rewritten: %s", raw)
	}
}

func TestXrayBuildConfigWithFragmentIsLoadable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "source.yaml")
	if err := os.WriteFile(path, []byte("proxies: []\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	raw, err := xrayCore.buildConfig(startOptions{ConfigPath: path, XrayFragment: true})
	if err != nil {
		t.Fatalf("buildConfig: %v", err)
	}
	if !bytes.Contains(raw, []byte(`"fragment"`)) {
		t.Fatalf("fragment settings missing: %s", raw)
	}
	if _, err := xserial.LoadJSONConfig(bytes.NewReader(raw)); err != nil {
		t.Fatalf("fragmented config rejected by xray: %v\n%s", err, raw)
	}
}

func TestXrayValidateConfigRejectsMissingFile(t *testing.T) {
	if err := xrayCore.validateConfig(filepath.Join(t.TempDir(), "absent.yaml")); err == nil {
		t.Fatal("expected an error for a missing config file")
	}
	if err := xrayCore.validateConfig(""); err == nil {
		t.Fatal("expected an error for an empty config path")
	}
}

func TestResolveKernel(t *testing.T) {
	for name, want := range map[string]kernel{
		KernelMihomo: mihomoCore,
		KernelXray:   xrayCore,
	} {
		got, err := resolveKernel(name)
		if err != nil {
			t.Fatalf("resolveKernel(%q): %v", name, err)
		}
		if got != want {
			t.Fatalf("resolveKernel(%q) returned %s", name, got.name())
		}
	}
	if _, err := resolveKernel("singbox"); err == nil {
		t.Fatal("expected an error for an unknown kernel")
	}
}
