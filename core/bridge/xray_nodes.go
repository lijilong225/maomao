package bridge

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/common/yaml"
	xconf "github.com/xtls/xray-core/infra/conf"
)

// ExtractNodes turns the proxies of a mihomo config into xray outbounds.
//
// Every proxy produces one record, including the ones xray cannot run, so the host
// can list the whole subscription and explain the gaps instead of silently
// dropping entries. Proxy groups and providers are ignored: xray selects nodes by
// routing, not by group.
func ExtractNodes(configYAML string) (string, error) {
	if strings.TrimSpace(configYAML) == "" {
		return "", errors.New("config is empty")
	}

	var doc struct {
		Proxies []map[string]any `yaml:"proxies"`
	}
	if err := yaml.Unmarshal([]byte(configYAML), &doc); err != nil {
		return "", fmt.Errorf("invalid config yaml: %w", err)
	}

	nodes := make([]xrayNode, 0, len(doc.Proxies))
	taken := make(map[string]bool, len(doc.Proxies))
	for i, proxy := range doc.Proxies {
		node := convertNode(proxy)
		if node.Name == "" {
			node.Name = fmt.Sprintf("node-%d", i+1)
		}
		node.Tag = uniqueNodeTag(taken, node.Name)
		if node.Outbound != nil {
			node.Outbound.Tag = node.Tag
		}
		nodes = append(nodes, node)
	}

	buf, err := json.Marshal(xrayNodeList{Nodes: nodes})
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

type xrayNodeList struct {
	Nodes []xrayNode `json:"nodes"`
}

type xrayNode struct {
	// Name is the subscription's label, Tag the deduplicated routing identifier.
	Name      string        `json:"name"`
	Tag       string        `json:"tag"`
	Type      string        `json:"type"`
	Server    string        `json:"server"`
	Port      int           `json:"port"`
	Supported bool          `json:"supported"`
	Reason    string        `json:"reason,omitempty"`
	Outbound  *xrayOutbound `json:"outbound,omitempty"`
}

func convertNode(proxy map[string]any) xrayNode {
	node := xrayNode{
		Name:   nodeString(proxy, "name"),
		Type:   strings.ToLower(nodeString(proxy, "type")),
		Server: nodeString(proxy, "server"),
		Port:   nodeInt(proxy, "port"),
	}

	outbound, err := buildNodeOutbound(node.Type, proxy)
	if err != nil {
		node.Reason = err.Error()
		return node
	}
	if err := validateNodeOutbound(outbound); err != nil {
		node.Reason = err.Error()
		return node
	}

	node.Supported = true
	node.Outbound = outbound
	return node
}

// uniqueNodeTag keeps tags unique because xray rejects duplicate outbound tags
// while subscriptions happily repeat names.
func uniqueNodeTag(taken map[string]bool, name string) string {
	tag := name
	for i := 2; taken[tag]; i++ {
		tag = fmt.Sprintf("%s #%d", name, i)
	}
	taken[tag] = true
	return tag
}

func buildNodeOutbound(kind string, proxy map[string]any) (*xrayOutbound, error) {
	server := nodeString(proxy, "server")
	port := nodeInt(proxy, "port")
	if server == "" || port <= 0 || port > 65535 {
		return nil, errors.New("missing or invalid server address")
	}

	var (
		protocol string
		settings any
		// Protocols that are always wrapped in TLS carry no "tls" flag in mihomo.
		tlsImplied bool
	)
	switch kind {
	case "vless":
		flow := nodeString(proxy, "flow")
		switch flow {
		case "", "xtls-rprx-vision", "xtls-rprx-vision-udp443":
		default:
			return nil, fmt.Errorf("unsupported vless flow %q", flow)
		}
		protocol = "vless"
		settings = xrayVlessSettings{
			Address:    server,
			Port:       port,
			ID:         nodeString(proxy, "uuid"),
			Flow:       flow,
			Encryption: "none",
		}
	case "vmess":
		protocol = "vmess"
		settings = xrayVmessSettings{
			Address:  server,
			Port:     port,
			ID:       nodeString(proxy, "uuid"),
			Security: nodeString(proxy, "cipher"),
		}
	case "trojan":
		protocol = "trojan"
		tlsImplied = true
		settings = xrayTrojanSettings{
			Address:  server,
			Port:     port,
			Password: nodeString(proxy, "password"),
		}
	case "ss", "shadowsocks":
		if plugin := nodeString(proxy, "plugin"); plugin != "" {
			return nil, fmt.Errorf("unsupported shadowsocks plugin %q", plugin)
		}
		method := strings.ToLower(nodeString(proxy, "cipher"))
		if !xrayShadowsocksMethods[method] {
			return nil, fmt.Errorf("unsupported shadowsocks cipher %q", method)
		}
		protocol = "shadowsocks"
		settings = xrayShadowsocksSettings{
			Address:    server,
			Port:       port,
			Method:     method,
			Password:   nodeString(proxy, "password"),
			UoT:        nodeBool(proxy, "udp-over-tcp"),
			UoTVersion: nodeInt(proxy, "udp-over-tcp-version"),
		}
	case "socks5", "socks":
		protocol = "socks"
		settings = xraySocksSettings{
			Address:  server,
			Port:     port,
			User:     nodeString(proxy, "username"),
			Password: nodeString(proxy, "password"),
		}
	case "http", "https":
		protocol = "http"
		settings = xrayHTTPSettings{
			Address:  server,
			Port:     port,
			User:     nodeString(proxy, "username"),
			Password: nodeString(proxy, "password"),
		}
	default:
		return nil, fmt.Errorf("unsupported protocol %q", kind)
	}

	stream, err := buildNodeStream(proxy, tlsImplied)
	if err != nil {
		return nil, err
	}

	rawSettings, err := json.Marshal(settings)
	if err != nil {
		return nil, err
	}
	rawStream, err := json.Marshal(stream)
	if err != nil {
		return nil, err
	}
	return &xrayOutbound{Protocol: protocol, Settings: rawSettings, StreamSettings: rawStream}, nil
}

func buildNodeStream(proxy map[string]any, tlsImplied bool) (*xrayStreamSettings, error) {
	network := strings.ToLower(nodeString(proxy, "network"))
	if network == "" {
		network = "tcp"
	}

	stream := &xrayStreamSettings{}
	hostHint := ""
	switch network {
	case "tcp", "raw", "http":
		// mihomo's "http" is HTTP header obfuscation over TCP, not xray's removed
		// h2 transport, so both land on the raw transport.
		stream.Network = "tcp"
		if opts := nodeMap(proxy, "http-opts"); len(opts) > 0 {
			stream.RAWSettings = &xrayRawSettings{Header: buildRawHTTPHeader(opts)}
		} else if network == "http" {
			stream.RAWSettings = &xrayRawSettings{Header: &xrayRawHTTPHeader{Type: "http"}}
		}
	case "ws":
		opts := nodeMap(proxy, "ws-opts")
		ws := buildWebSocketSettings(opts)
		hostHint = ws.Host
		if nodeBool(opts, "v2ray-http-upgrade") {
			stream.Network = "httpupgrade"
			stream.HTTPUpgradeSettings = ws
		} else {
			stream.Network = "ws"
			stream.WSSettings = ws
		}
	case "grpc":
		opts := nodeMap(proxy, "grpc-opts")
		stream.Network = "grpc"
		stream.GRPCSettings = &xrayGRPCSettings{
			ServiceName: nodeString(opts, "grpc-service-name"),
			UserAgent:   nodeString(opts, "grpc-user-agent"),
		}
	default:
		return nil, fmt.Errorf("unsupported transport %q", network)
	}

	fingerprint := strings.ToLower(nodeString(proxy, "client-fingerprint"))
	switch fingerprint {
	case "unsafe", "hellogolang":
		return nil, fmt.Errorf("unsupported client fingerprint %q", fingerprint)
	}
	sni := firstNonEmpty(nodeString(proxy, "servername"), nodeString(proxy, "sni"), hostHint)

	if reality := nodeMap(proxy, "reality-opts"); len(reality) > 0 {
		key := nodeString(reality, "public-key")
		if raw, err := base64.RawURLEncoding.DecodeString(key); err != nil || len(raw) != 32 {
			return nil, errors.New("invalid reality public-key")
		}
		stream.Security = "reality"
		stream.RealitySettings = &xrayRealitySettings{
			ServerName:  sni,
			Fingerprint: fingerprint,
			PublicKey:   key,
			ShortID:     nodeString(reality, "short-id"),
		}
		return stream, nil
	}

	if nodeBool(proxy, "tls") || tlsImplied {
		stream.Security = "tls"
		stream.TLSSettings = &xrayTLSSettings{
			ServerName:    sni,
			AllowInsecure: nodeBool(proxy, "skip-cert-verify"),
			ALPN:          nodeStringSlice(proxy, "alpn"),
			Fingerprint:   fingerprint,
		}
	}
	return stream, nil
}

func buildWebSocketSettings(opts map[string]any) *xrayWebSocketSettings {
	ws := &xrayWebSocketSettings{Path: nodeString(opts, "path")}
	headers := nodeStringMap(opts, "headers")
	for name, value := range headers {
		if strings.EqualFold(name, "host") {
			ws.Host = value
			delete(headers, name)
		}
	}
	if len(headers) > 0 {
		ws.Headers = headers
	}
	return ws
}

func buildRawHTTPHeader(opts map[string]any) *xrayRawHTTPHeader {
	header := &xrayRawHTTPHeader{Type: "http"}
	request := xrayRawHTTPRequest{
		Method:  nodeString(opts, "method"),
		Path:    nodeStringSlice(opts, "path"),
		Headers: nodeHeaderMap(opts, "headers"),
	}
	if request.Method != "" || len(request.Path) > 0 || len(request.Headers) > 0 {
		header.Request = &request
	}
	return header
}

// validateNodeOutbound runs the generated outbound through xray's own config
// builder so a node is only reported as usable if the core would accept it.
func validateNodeOutbound(out *xrayOutbound) error {
	detour := xconf.OutboundDetourConfig{Protocol: out.Protocol}
	if len(out.Settings) > 0 {
		raw := json.RawMessage(out.Settings)
		detour.Settings = &raw
	}
	if len(out.StreamSettings) > 0 {
		var stream xconf.StreamConfig
		if err := json.Unmarshal(out.StreamSettings, &stream); err != nil {
			return err
		}
		detour.StreamSetting = &stream
	}
	_, err := detour.Build()
	return err
}

// Ciphers xray's cipherFromString accepts. Notably 2022-blake3-* is absent.
var xrayShadowsocksMethods = map[string]bool{
	"aes-128-gcm":             true,
	"aead_aes_128_gcm":        true,
	"aes-256-gcm":             true,
	"aead_aes_256_gcm":        true,
	"chacha20-poly1305":       true,
	"aead_chacha20_poly1305":  true,
	"chacha20-ietf-poly1305":  true,
	"xchacha20-poly1305":      true,
	"aead_xchacha20_poly1305": true,
	"xchacha20-ietf-poly1305": true,
	"none":                    true,
	"plain":                   true,
}

type xrayStreamSettings struct {
	Network             string                 `json:"network"`
	Security            string                 `json:"security,omitempty"`
	TLSSettings         *xrayTLSSettings       `json:"tlsSettings,omitempty"`
	RealitySettings     *xrayRealitySettings   `json:"realitySettings,omitempty"`
	RAWSettings         *xrayRawSettings       `json:"rawSettings,omitempty"`
	WSSettings          *xrayWebSocketSettings `json:"wsSettings,omitempty"`
	HTTPUpgradeSettings *xrayWebSocketSettings `json:"httpupgradeSettings,omitempty"`
	GRPCSettings        *xrayGRPCSettings      `json:"grpcSettings,omitempty"`
}

type xrayTLSSettings struct {
	ServerName    string   `json:"serverName,omitempty"`
	AllowInsecure bool     `json:"allowInsecure,omitempty"`
	ALPN          []string `json:"alpn,omitempty"`
	Fingerprint   string   `json:"fingerprint,omitempty"`
}

type xrayRealitySettings struct {
	ServerName  string `json:"serverName,omitempty"`
	Fingerprint string `json:"fingerprint,omitempty"`
	PublicKey   string `json:"publicKey"`
	ShortID     string `json:"shortId,omitempty"`
}

type xrayRawSettings struct {
	Header *xrayRawHTTPHeader `json:"header,omitempty"`
}

type xrayRawHTTPHeader struct {
	Type    string              `json:"type"`
	Request *xrayRawHTTPRequest `json:"request,omitempty"`
}

type xrayRawHTTPRequest struct {
	Method  string              `json:"method,omitempty"`
	Path    []string            `json:"path,omitempty"`
	Headers map[string][]string `json:"headers,omitempty"`
}

type xrayWebSocketSettings struct {
	Host    string            `json:"host,omitempty"`
	Path    string            `json:"path,omitempty"`
	Headers map[string]string `json:"headers,omitempty"`
}

type xrayGRPCSettings struct {
	ServiceName string `json:"serviceName,omitempty"`
	UserAgent   string `json:"user_agent,omitempty"`
}

type xrayVlessSettings struct {
	Address    string `json:"address"`
	Port       int    `json:"port"`
	ID         string `json:"id"`
	Flow       string `json:"flow,omitempty"`
	Encryption string `json:"encryption"`
}

type xrayVmessSettings struct {
	Address  string `json:"address"`
	Port     int    `json:"port"`
	ID       string `json:"id"`
	Security string `json:"security,omitempty"`
}

type xrayTrojanSettings struct {
	Address  string `json:"address"`
	Port     int    `json:"port"`
	Password string `json:"password"`
}

type xrayShadowsocksSettings struct {
	Address    string `json:"address"`
	Port       int    `json:"port"`
	Method     string `json:"method"`
	Password   string `json:"password"`
	UoT        bool   `json:"uot,omitempty"`
	UoTVersion int    `json:"uotVersion,omitempty"`
}

type xraySocksSettings struct {
	Address  string `json:"address"`
	Port     int    `json:"port"`
	User     string `json:"user,omitempty"`
	Password string `json:"pass,omitempty"`
}

type xrayHTTPSettings struct {
	Address  string `json:"address"`
	Port     int    `json:"port"`
	User     string `json:"user,omitempty"`
	Password string `json:"pass,omitempty"`
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func nodeString(m map[string]any, key string) string {
	value, _ := m[key].(string)
	return value
}

func nodeBool(m map[string]any, key string) bool {
	value, _ := m[key].(bool)
	return value
}

func nodeInt(m map[string]any, key string) int {
	switch value := m[key].(type) {
	case int:
		return value
	case int64:
		return int(value)
	case uint16:
		return int(value)
	case float64:
		return int(value)
	case string:
		n, err := strconv.Atoi(strings.TrimSpace(value))
		if err != nil {
			return 0
		}
		return n
	default:
		return 0
	}
}

func nodeMap(m map[string]any, key string) map[string]any {
	switch value := m[key].(type) {
	case map[string]any:
		return value
	case map[any]any:
		out := make(map[string]any, len(value))
		for k, v := range value {
			if name, ok := k.(string); ok {
				out[name] = v
			}
		}
		return out
	default:
		return nil
	}
}

func nodeStringMap(m map[string]any, key string) map[string]string {
	raw := nodeMap(m, key)
	out := make(map[string]string, len(raw))
	for name, value := range raw {
		if text, ok := value.(string); ok {
			out[name] = text
		}
	}
	return out
}

func nodeHeaderMap(m map[string]any, key string) map[string][]string {
	raw := nodeMap(m, key)
	if len(raw) == 0 {
		return nil
	}
	out := make(map[string][]string, len(raw))
	for name, value := range raw {
		if values := coerceStringSlice(value); len(values) > 0 {
			out[name] = values
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func nodeStringSlice(m map[string]any, key string) []string {
	return coerceStringSlice(m[key])
}

func coerceStringSlice(value any) []string {
	switch typed := value.(type) {
	case []string:
		return typed
	case string:
		if typed == "" {
			return nil
		}
		return []string{typed}
	case []any:
		out := make([]string, 0, len(typed))
		for _, item := range typed {
			if text, ok := item.(string); ok && text != "" {
				out = append(out, text)
			}
		}
		if len(out) == 0 {
			return nil
		}
		return out
	default:
		return nil
	}
}
