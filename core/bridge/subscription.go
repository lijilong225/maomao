package bridge

import (
	"errors"
	"fmt"
	"strings"

	"github.com/metacubex/mihomo/common/convert"
	"github.com/metacubex/mihomo/common/yaml"
)

// ConvertSubscription normalizes a raw subscription payload into mihomo YAML.
//
// It accepts either a mihomo/Clash YAML config or a V2Ray-style share-link list
// (optionally base64 encoded), reusing the core's own parsers so every protocol
// the core supports is understood without duplicating them on the host side.
func ConvertSubscription(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", errors.New("subscription body is empty")
	}

	var probe map[string]any
	if err := yaml.Unmarshal([]byte(trimmed), &probe); err == nil && isConfigLike(probe) {
		return trimmed, nil
	}

	proxies, err := convert.ConvertsV2Ray([]byte(trimmed))
	if err != nil {
		return "", fmt.Errorf("unrecognized subscription format: %w", err)
	}
	if len(proxies) == 0 {
		return "", errors.New("subscription contains no usable proxies")
	}

	buf, err := yaml.Marshal(map[string]any{"proxies": proxies})
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

// MergeConfig deep-merges patchYAML onto baseYAML and returns the result as YAML.
//
// Mappings merge recursively, any other value is replaced outright, and an
// explicit null in the patch deletes the key. This keeps user overrides
// declarative, so no scripting engine is needed.
func MergeConfig(baseYAML string, patchYAML string) (string, error) {
	base, err := decodeMapping(baseYAML, "base")
	if err != nil {
		return "", err
	}
	patch, err := decodeMapping(patchYAML, "patch")
	if err != nil {
		return "", err
	}

	buf, err := yaml.Marshal(mergeMapping(base, patch))
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

func decodeMapping(raw string, label string) (map[string]any, error) {
	if strings.TrimSpace(raw) == "" {
		return map[string]any{}, nil
	}
	var out map[string]any
	if err := yaml.Unmarshal([]byte(raw), &out); err != nil {
		return nil, fmt.Errorf("invalid %s yaml: %w", label, err)
	}
	if out == nil {
		return map[string]any{}, nil
	}
	return out, nil
}

// isConfigLike distinguishes a real config from a YAML document that merely
// happens to parse, such as a single share link containing a colon.
func isConfigLike(doc map[string]any) bool {
	for _, key := range [...]string{"proxies", "proxy-providers", "proxy-groups", "rules", "mode"} {
		if _, ok := doc[key]; ok {
			return true
		}
	}
	return false
}

func mergeMapping(base, patch map[string]any) map[string]any {
	out := make(map[string]any, len(base)+len(patch))
	for k, v := range base {
		out[k] = v
	}
	for k, v := range patch {
		if v == nil {
			delete(out, k)
			continue
		}
		if nested, ok := asMapping(v); ok {
			if existing, ok := asMapping(out[k]); ok {
				out[k] = mergeMapping(existing, nested)
				continue
			}
		}
		out[k] = v
	}
	return out
}

// asMapping normalizes both map[string]any and yaml.v3's map[any]any shape.
func asMapping(value any) (map[string]any, bool) {
	switch typed := value.(type) {
	case map[string]any:
		return typed, true
	case map[any]any:
		out := make(map[string]any, len(typed))
		for k, v := range typed {
			out[fmt.Sprint(k)] = v
		}
		return out, true
	default:
		return nil, false
	}
}
