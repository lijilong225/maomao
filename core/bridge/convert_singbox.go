package bridge

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/metacubex/mihomo/common/yaml"
	"github.com/xmdhs/clash2singbox/convert"
	"github.com/xmdhs/clash2singbox/model"
	"github.com/xmdhs/clash2singbox/model/clash"
	"github.com/xmdhs/clash2singbox/model/singbox"
)

const (
	singboxSelectTag    = "select"
	singboxURLTestTag   = "urltest"
	singboxDirectTag    = "direct"
	singboxBlockTag     = "block"
	singboxTunTag       = "tun-in"
	singboxDNSRemoteTag = "dns-remote"
	singboxDNSDirectTag = "dns-direct"

	singboxTunIPv6Address   = "fdfe:dcba:9876::1/126"
	singboxDefaultRemoteDNS = "1.1.1.1"
	singboxDefaultDirectDNS = "223.5.5.5"
	singboxURLTestURL       = "https://www.gstatic.com/generate_204"
	singboxURLTestInterval  = "3m"
)

// singboxConfig is the shape of the generated config.
//
// Only the fields we actually emit are modelled: sing-box rejects unknown keys,
// so a hand-rolled struct keeps the output minimal and the key order readable
// instead of the alphabetical order a map would produce.
type singboxConfig struct {
	DNS       singboxDNSOptions          `json:"dns"`
	Inbounds  []singboxTunInbound        `json:"inbounds"`
	Outbounds []singbox.SingBoxOut       `json:"outbounds"`
	Endpoints []*singbox.SingBoxEndpoint `json:"endpoints,omitempty"`
	Route     singboxRouteOptions        `json:"route"`
}

type singboxDNSOptions struct {
	Servers  []singboxDNSServer `json:"servers"`
	Final    string             `json:"final,omitempty"`
	Strategy string             `json:"strategy,omitempty"`
}

type singboxDNSServer struct {
	Type   string `json:"type"`
	Tag    string `json:"tag"`
	Server string `json:"server"`
	Detour string `json:"detour,omitempty"`
}

type singboxTunInbound struct {
	Type      string   `json:"type"`
	Tag       string   `json:"tag"`
	Address   []string `json:"address"`
	MTU       uint32   `json:"mtu"`
	AutoRoute bool     `json:"auto_route"`
	Stack     string   `json:"stack"`
	DNSMode   string   `json:"dns_mode"`
}

type singboxRouteOptions struct {
	Rules                 []json.RawMessage `json:"rules,omitempty"`
	Final                 string            `json:"final,omitempty"`
	AutoDetectInterface   bool              `json:"auto_detect_interface"`
	DefaultDomainResolver string            `json:"default_domain_resolver,omitempty"`
}

// singboxGroup is a proxy group whose membership is still being validated.
type singboxGroup struct {
	name         string
	tag          string
	outboundType string
	members      []string
}

// ConvertToSingbox translates a mihomo/Clash YAML config into sing-box JSON.
//
// Subscriptions are authored for mihomo, so profiles keep living in that format
// and only the sing-box engine sees the translated result. Proxy definitions and
// relay chains come from clash2singbox; proxy groups, routing, DNS and the TUN
// inbound are synthesized here because that library only ships templates for
// sing-box 1.11 and older, whose DNS and geo options are hard errors in 1.14.
func ConvertToSingbox(yamlText string) (string, error) {
	trimmed := strings.TrimSpace(yamlText)
	if trimmed == "" {
		return "", errors.New("config is empty")
	}

	var source clash.Clash
	if err := yaml.Unmarshal([]byte(trimmed), &source); err != nil {
		return "", fmt.Errorf("invalid mihomo yaml: %w", err)
	}
	warnUnconvertedMihomoKeys(trimmed)

	// Clash2sing joins per-proxy failures instead of aborting, so one
	// unsupported protocol must not take the whole subscription down.
	outbounds, endpoints, partial := convert.Clash2sing(source, model.SINGLATEST)
	if partial != nil {
		emitLog("warning", "singbox convert: skipped some proxies: "+partial.Error())
	}
	if len(outbounds) == 0 && len(endpoints) == 0 {
		if partial != nil {
			return "", fmt.Errorf("no proxy could be converted for sing-box: %w", partial)
		}
		return "", errors.New("no proxy could be converted for sing-box")
	}

	tags := newSingboxTagAllocator()
	outboundTags := make([]string, len(outbounds))
	for i := range outbounds {
		outboundTags[i] = tags.claim(outbounds[i].Tag, fmt.Sprintf("proxy-%d", i+1))
	}
	endpointTags := make([]string, len(endpoints))
	for i := range endpoints {
		endpointTags[i] = tags.claim(endpoints[i].Tag, fmt.Sprintf("endpoint-%d", i+1))
	}

	// Selectable tags, in subscription order. Ignored and Visible mark the inner
	// hops of shadow-tls and relay chains: they stay in outbounds so detour can
	// reach them, but they must never be offered as a proxy.
	selectable := make([]string, 0, len(outbounds)+len(endpoints))
	isSelectable := map[string]bool{}
	for i := range outbounds {
		outbounds[i].Tag = outboundTags[i]
		outbounds[i].Detour = tags.resolve(outbounds[i].Detour)
		if outbounds[i].Ignored || len(outbounds[i].Visible) != 0 {
			continue
		}
		isSelectable[outboundTags[i]] = true
		selectable = append(selectable, outboundTags[i])
	}
	for i := range endpoints {
		endpoints[i].Tag = endpointTags[i]
		endpoints[i].Detour = tags.resolve(endpoints[i].Detour)
		isSelectable[endpointTags[i]] = true
		selectable = append(selectable, endpointTags[i])
	}
	if len(selectable) == 0 {
		return "", errors.New("config contains no selectable proxy for sing-box")
	}

	groups, groupTags := planSingboxGroups(source.ProxyGroup, tags)
	pruneSingboxGroups(groups, groupTags, isSelectable, tags)

	all := make([]singbox.SingBoxOut, 0, len(outbounds)+len(groups)+4)
	all = append(all, singbox.SingBoxOut{
		Type:      "selector",
		Tag:       singboxSelectTag,
		Outbounds: buildSingboxSelectMembers(groups, selectable),
		Default:   singboxURLTestTag,
	})
	all = append(all, newSingboxURLTest(singboxURLTestTag, selectable))
	for _, group := range groups {
		if group.tag == "" {
			continue
		}
		if group.outboundType == "urltest" {
			all = append(all, newSingboxURLTest(group.tag, group.members))
			continue
		}
		all = append(all, singbox.SingBoxOut{
			Type:      group.outboundType,
			Tag:       group.tag,
			Outbounds: group.members,
			Default:   group.members[0],
		})
	}
	all = append(all, outbounds...)
	all = append(all, singbox.SingBoxOut{Type: "direct", Tag: singboxDirectTag})
	all = append(all, singbox.SingBoxOut{Type: "block", Tag: singboxBlockTag})

	config := singboxConfig{
		DNS: singboxDNSOptions{
			// The host feeds mihomo the system resolvers, but sing-box has no
			// such hook, so the defaults have to be explicit. A bare "local"
			// transport is useless on Android, where /etc/resolv.conf is absent.
			Servers: []singboxDNSServer{
				{Type: "udp", Tag: singboxDNSRemoteTag, Server: singboxDefaultRemoteDNS, Detour: singboxSelectTag},
				{Type: "udp", Tag: singboxDNSDirectTag, Server: singboxDefaultDirectDNS, Detour: singboxDirectTag},
			},
			Final:    singboxDNSRemoteTag,
			Strategy: "prefer_ipv4",
		},
		// The engine needs a TUN inbound in the file itself: TunOptions reads the
		// address, MTU and DNS from here before the interface is created, and the
		// remaining fields are overridden per start request.
		Inbounds: []singboxTunInbound{{
			Type:      "tun",
			Tag:       singboxTunTag,
			Address:   []string{defaultSingboxTunAddress, singboxTunIPv6Address},
			MTU:       defaultTunMTU,
			AutoRoute: true,
			Stack:     "gvisor",
			// DNS hijacking lives on the inbound so no hijack-dns route rule is
			// needed; sing-box validates that action against an action-only
			// schema, which rejects the matcher fields such a rule would need.
			DNSMode: "hijack",
		}},
		Outbounds: all,
		Endpoints: endpoints,
		Route: singboxRouteOptions{
			// geoip and geosite are removed in sing-box 1.12+ and remote rule
			// sets abort startup when the first download fails, so routing stays
			// deliberately minimal.
			Rules: []json.RawMessage{
				json.RawMessage(`{"action":"sniff"}`),
				json.RawMessage(`{"ip_is_private":true,"outbound":"` + singboxDirectTag + `"}`),
			},
			Final:                 singboxSelectTag,
			AutoDetectInterface:   true,
			DefaultDomainResolver: singboxDNSDirectTag,
		},
	}

	buf, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

func newSingboxURLTest(tag string, members []string) singbox.SingBoxOut {
	return singbox.SingBoxOut{
		Type:      "urltest",
		Tag:       tag,
		Outbounds: members,
		URL:       singboxURLTestURL,
		Interval:  singboxURLTestInterval,
	}
}

func buildSingboxSelectMembers(groups []*singboxGroup, selectable []string) []string {
	members := make([]string, 0, len(selectable)+len(groups)+2)
	members = append(members, singboxURLTestTag)
	for _, group := range groups {
		if group.tag != "" {
			members = append(members, group.tag)
		}
	}
	members = append(members, selectable...)
	return append(members, singboxDirectTag)
}

// singboxTagAllocator hands out unique outbound tags and remembers the renames.
//
// sing-box rejects duplicate tags across outbounds and endpoints, and the
// generated selector, urltest, direct and block outbounds share that namespace,
// so subscription names have to be de-duplicated before anything references
// them.
type singboxTagAllocator struct {
	used    map[string]bool
	renamed map[string]string
	kept    map[string]bool
}

func newSingboxTagAllocator() *singboxTagAllocator {
	return &singboxTagAllocator{
		used: map[string]bool{
			singboxSelectTag:  true,
			singboxURLTestTag: true,
			singboxDirectTag:  true,
			singboxBlockTag:   true,
		},
		renamed: map[string]string{},
		kept:    map[string]bool{},
	}
}

func (a *singboxTagAllocator) claim(original string, fallback string) string {
	base := strings.TrimSpace(original)
	if base == "" {
		base = fallback
	}
	final := base
	for i := 2; a.used[final]; i++ {
		final = fmt.Sprintf("%s-%d", base, i)
	}
	a.used[final] = true

	if final == original {
		a.kept[original] = true
		return final
	}
	// A duplicate name must not hijack references aimed at the first holder of
	// that name, so only the loser of a collision records a rename.
	if original != "" && !a.kept[original] {
		if _, exists := a.renamed[original]; !exists {
			a.renamed[original] = final
		}
	}
	return final
}

func (a *singboxTagAllocator) resolve(name string) string {
	if to, ok := a.renamed[name]; ok {
		return to
	}
	return name
}

// planSingboxGroups reserves a tag for every convertible mihomo proxy group.
//
// relay groups are skipped because clash2singbox already flattened them into
// detour chains.
func planSingboxGroups(source []clash.ProxyGroup, tags *singboxTagAllocator) ([]*singboxGroup, map[string]string) {
	groups := make([]*singboxGroup, 0, len(source))
	groupTags := make(map[string]string, len(source))
	for _, group := range source {
		name := strings.TrimSpace(group.Name)
		if name == "" {
			continue
		}
		if _, exists := groupTags[name]; exists {
			continue
		}
		outboundType := ""
		switch strings.ToLower(strings.TrimSpace(group.Type)) {
		case "relay":
			continue
		case "select":
			outboundType = "selector"
		case "url-test", "fallback":
			outboundType = "urltest"
		case "load-balance":
			// sing-box has no load balancer, so pick the closest behaviour.
			outboundType = "urltest"
			emitLog("warning", "singbox convert: load-balance group "+name+" downgraded to urltest")
		default:
			emitLog("warning", "singbox convert: unsupported proxy group type "+group.Type+" for "+name)
			continue
		}
		tag := tags.claim(name, "group")
		groupTags[name] = tag
		groups = append(groups, &singboxGroup{
			name:         name,
			tag:          tag,
			outboundType: outboundType,
			members:      group.Proxies,
		})
	}
	return groups, groupTags
}

// pruneSingboxGroups resolves group membership and drops the groups that end up
// empty, clearing their tag.
//
// Both selector and urltest abort with "missing tags" when their outbound list
// is empty, and dropping one group can empty another, so this runs to a
// fixpoint.
func pruneSingboxGroups(groups []*singboxGroup, groupTags map[string]string, isSelectable map[string]bool, tags *singboxTagAllocator) {
	raw := make([][]string, len(groups))
	for i, group := range groups {
		raw[i] = group.members
	}
	for {
		changed := false
		for i, group := range groups {
			if group.tag == "" {
				continue
			}
			members := make([]string, 0, len(raw[i]))
			seen := map[string]bool{}
			for _, member := range raw[i] {
				resolved := resolveSingboxMember(member, group.tag, groupTags, isSelectable, tags)
				if resolved == "" || seen[resolved] {
					continue
				}
				seen[resolved] = true
				members = append(members, resolved)
			}
			if len(members) == 0 {
				emitLog("warning", "singbox convert: proxy group "+group.name+" has no usable member, skipped")
				delete(groupTags, group.name)
				group.tag = ""
				changed = true
				continue
			}
			group.members = members
		}
		if !changed {
			return
		}
	}
}

func resolveSingboxMember(member string, self string, groupTags map[string]string, isSelectable map[string]bool, tags *singboxTagAllocator) string {
	name := strings.TrimSpace(member)
	if name == "" {
		return ""
	}
	switch strings.ToUpper(name) {
	case "DIRECT":
		return singboxDirectTag
	case "REJECT", "REJECT-DROP":
		return singboxBlockTag
	case "PASS", "GLOBAL", "COMPATIBLE":
		return ""
	}
	if tag, ok := groupTags[name]; ok {
		if tag == self {
			return ""
		}
		return tag
	}
	if tag := tags.resolve(name); isSelectable[tag] {
		return tag
	}
	return ""
}

// warnUnconvertedMihomoKeys tells the user which parts of their profile the
// sing-box engine will ignore, since silently dropping rules would look like a
// routing bug.
func warnUnconvertedMihomoKeys(yamlText string) {
	doc, err := decodeMapping(yamlText, "config")
	if err != nil {
		return
	}
	for _, key := range [...]string{"proxy-providers", "rule-providers", "rules", "sub-rules", "dns", "hosts"} {
		if _, ok := doc[key]; !ok {
			continue
		}
		emitLog("warning", "singbox convert: "+key+" is not translated, sing-box uses the generated defaults")
	}
}
