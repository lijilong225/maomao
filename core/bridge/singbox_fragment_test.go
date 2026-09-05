package bridge

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	box "github.com/sagernet/sing-box"
	sbconstant "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
)

// singboxOptionsWith parses the converted test config and applies the host
// overrides, which is the only place fragmentation gets injected.
func singboxOptionsWith(t *testing.T, start startOptions) (context.Context, option.Options) {
	t.Helper()

	raw, err := ConvertToSingbox(singboxTestConfig)
	if err != nil {
		t.Fatalf("ConvertToSingbox: %v", err)
	}
	path := filepath.Join(t.TempDir(), "runtime.json")
	if err := os.WriteFile(path, []byte(raw), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	engine := &singboxEngine{}
	ctx, opts, err := engine.parse(path, start)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	applySingboxOverrides(&opts, start, controllerInfo{Addr: "127.0.0.1:0"})
	return ctx, opts
}

// fragmentRuleCount reports how many route-options rules ask for TLS fragmentation.
func fragmentRuleCount(rules []option.Rule) int {
	count := 0
	for _, rule := range rules {
		if rule.Type != sbconstant.RuleTypeDefault {
			continue
		}
		if rule.DefaultOptions.Action != sbconstant.RuleActionTypeRouteOptions {
			continue
		}
		if rule.DefaultOptions.RouteOptionsOptions.TLSFragment {
			count++
		}
	}
	return count
}

func TestSingboxOverridesInjectFragmentRule(t *testing.T) {
	_, opts := singboxOptionsWith(t, startOptions{TLSFragment: true})

	if opts.Route == nil || len(opts.Route.Rules) == 0 {
		t.Fatal("route rules are empty, expected the fragment rule")
	}
	if got := fragmentRuleCount(opts.Route.Rules); got != 1 {
		t.Fatalf("expected exactly one fragment rule, got %d", got)
	}

	first := opts.Route.Rules[0]
	if first.DefaultOptions.Action != sbconstant.RuleActionTypeRouteOptions {
		t.Errorf("fragment rule is not first, got action %q", first.DefaultOptions.Action)
	}
	if !first.DefaultOptions.RouteOptionsOptions.TLSFragment {
		t.Error("first rule does not enable tls_fragment")
	}
	// Both at once is rejected by sing-box.
	if first.DefaultOptions.RouteOptionsOptions.TLSRecordFragment {
		t.Error("tls_record_fragment must stay off, it is exclusive with tls_fragment")
	}
	if network := first.DefaultOptions.Network; len(network) != 1 || network[0] != "tcp" {
		t.Errorf("fragment rule should be scoped to tcp, got %v", network)
	}
	// The config's own rules have to survive, and a route-options action must not
	// swallow them.
	if len(opts.Route.Rules) < 2 {
		t.Error("fragment rule replaced the config's rules instead of preceding them")
	}
}

func TestSingboxOverridesOmitFragmentRuleWhenDisabled(t *testing.T) {
	_, opts := singboxOptionsWith(t, startOptions{})

	if opts.Route == nil {
		t.Fatal("route options are nil")
	}
	if got := fragmentRuleCount(opts.Route.Rules); got != 0 {
		t.Fatalf("expected no fragment rule, got %d", got)
	}
}

func TestSingboxFragmentConfigIsLoadable(t *testing.T) {
	ctx, opts := singboxOptionsWith(t, startOptions{TLSFragment: true})
	// The overrides point the cache at the process home directory, which tests do
	// not own.
	opts.Experimental.CacheFile.Path = filepath.Join(t.TempDir(), "cache.db")

	// The rule is built in Go rather than decoded from JSON, so it skips the
	// validation the option types perform on the way in. Constructing a real
	// instance is what proves sing-box accepts it.
	instance, err := box.New(box.Options{Context: ctx, Options: opts})
	if err != nil {
		t.Fatalf("sing-box rejected the fragment rule: %v", err)
	}
	if err := instance.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
}
