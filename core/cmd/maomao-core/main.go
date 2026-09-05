// Command maomao-core hosts the proxy core for desktop platforms, where the
// bridge cannot be linked into the app process the way gomobile does on Android.
//
// The host drives it over stdin/stdout with newline-delimited JSON: one request
// per line in, one frame per line out. Every frame carries a "type" so replies
// ("result") can be told apart from unsolicited events ("state", "log"). The
// method names, argument keys and error codes mirror the Android plugin so the
// Dart side can treat both backends the same.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"sync"

	"github.com/longfen/maomao/core/bridge"
	"github.com/sirupsen/logrus"
)

type request struct {
	ID     int64           `json:"id"`
	Method string          `json:"method"`
	Args   json.RawMessage `json:"args"`
}

type frameError struct {
	Code    string `json:"code"`
	Message string `json:"message,omitempty"`
}

type response struct {
	Type   string      `json:"type"`
	ID     int64       `json:"id"`
	Result any         `json:"result,omitempty"`
	Error  *frameError `json:"error,omitempty"`
}

// writer serializes the reply loop against the log pump goroutine.
type writer struct {
	mu  sync.Mutex
	enc *json.Encoder
}

func (w *writer) emit(frame any) {
	w.mu.Lock()
	defer w.mu.Unlock()
	_ = w.enc.Encode(frame)
}

type delegate struct{ out *writer }

// Protect only matters on Android, where sockets must escape the VPN.
func (d *delegate) Protect(int32) bool { return true }

func (d *delegate) OnLog(level string, payload string) {
	d.out.emit(map[string]string{"type": "log", "level": level, "payload": payload})
}

func (d *delegate) OnState(state string) {
	d.out.emit(map[string]string{"type": "state", "state": state})
}

func main() {
	home := flag.String("home", "", "core home directory")
	flag.Parse()

	// The core's logger writes every event to stdout, which is the protocol
	// stream here, so mute its backend and forward events through OnLog instead.
	logrus.SetOutput(io.Discard)

	out := &writer{enc: json.NewEncoder(os.Stdout)}

	if err := bridge.Init(*home); err != nil {
		fmt.Fprintln(os.Stderr, "init:", err)
		os.Exit(1)
	}
	bridge.RegisterDelegate(&delegate{out: out})
	// Replay the current state, as the Android event channel does on listen.
	out.emit(map[string]string{"type": "state", "state": bridge.State()})

	in := bufio.NewScanner(os.Stdin)
	// Requests carry whole config documents.
	in.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	for in.Scan() {
		line := bytes.TrimSpace(in.Bytes())
		if len(line) == 0 {
			continue
		}
		var req request
		if err := json.Unmarshal(line, &req); err != nil {
			out.emit(response{
				Type:  "result",
				Error: &frameError{Code: "invalid_request", Message: err.Error()},
			})
			continue
		}
		result, failure := dispatch(req)
		out.emit(response{Type: "result", ID: req.ID, Result: result, Error: failure})
	}

	// The host is gone, so drop the tunnel and release the TUN interface.
	bridge.Stop()
}

func dispatch(req request) (any, *frameError) {
	switch req.Method {
	case "version":
		return bridge.Version(), nil
	case "versionOf":
		var args struct {
			Engine string `json:"engine"`
		}
		if failure := decodeArgs(req.Args, &args); failure != nil {
			return nil, failure
		}
		return bridge.VersionOf(args.Engine), nil
	case "state":
		return bridge.State(), nil
	case "controllerInfo":
		return json.RawMessage(bridge.ControllerInfo()), nil
	case "traffic":
		return json.RawMessage(bridge.Traffic()), nil
	case "trafficTotal":
		return json.RawMessage(bridge.TrafficTotal()), nil
	case "validateConfig":
		var args struct {
			Engine     string `json:"engine"`
			ConfigPath string `json:"configPath"`
		}
		if failure := decodeArgs(req.Args, &args); failure != nil {
			return nil, failure
		}
		if args.ConfigPath == "" {
			return nil, &frameError{Code: "invalid_argument", Message: "configPath is required"}
		}
		if err := bridge.ValidateConfig(args.Engine, args.ConfigPath); err != nil {
			return nil, &frameError{Code: "invalid_config", Message: err.Error()}
		}
		return true, nil
	case "convertSubscription":
		var args struct {
			Raw string `json:"raw"`
		}
		if failure := decodeArgs(req.Args, &args); failure != nil {
			return nil, failure
		}
		converted, err := bridge.ConvertSubscription(args.Raw)
		if err != nil {
			return nil, &frameError{Code: "invalid_subscription", Message: err.Error()}
		}
		return converted, nil
	case "convertToSingbox":
		var args struct {
			Yaml string `json:"yaml"`
		}
		if failure := decodeArgs(req.Args, &args); failure != nil {
			return nil, failure
		}
		converted, err := bridge.ConvertToSingbox(args.Yaml)
		if err != nil {
			return nil, &frameError{Code: "invalid_config", Message: err.Error()}
		}
		return converted, nil
	case "mergeConfig":
		var args struct {
			Base  string `json:"base"`
			Patch string `json:"patch"`
		}
		if failure := decodeArgs(req.Args, &args); failure != nil {
			return nil, failure
		}
		merged, err := bridge.MergeConfig(args.Base, args.Patch)
		if err != nil {
			return nil, &frameError{Code: "invalid_config", Message: err.Error()}
		}
		return merged, nil
	case "start":
		return start(req.Args)
	case "stop":
		bridge.Stop()
		return nil, nil
	default:
		return nil, &frameError{Code: "unimplemented", Message: req.Method}
	}
}

// start doubles as reload, because the app reuses the start request to apply a
// new config to a running tunnel.
func start(raw json.RawMessage) (any, *frameError) {
	var args struct {
		Engine      string `json:"engine"`
		ConfigPath  string `json:"configPath"`
		TunStack    string `json:"tunStack"`
		TunMTU      uint32 `json:"tunMTU"`
		TLSFragment bool   `json:"tlsFragment"`
	}
	if failure := decodeArgs(raw, &args); failure != nil {
		return nil, failure
	}
	if args.ConfigPath == "" {
		return nil, &frameError{Code: "invalid_argument", Message: "configPath is required"}
	}

	// A reload cannot move the tunnel across cores, so an engine switch has to go
	// through the full start path instead.
	sameEngine := bridge.ActiveEngine() == bridge.NormalizedEngine(args.Engine)
	if bridge.State() == bridge.StateRunning && sameEngine {
		if err := bridge.Reload(args.ConfigPath); err != nil {
			return nil, &frameError{Code: "reload_failed", Message: err.Error()}
		}
		return nil, nil
	}

	stack := args.TunStack
	if stack == "" {
		stack = "gvisor"
	}
	options, err := json.Marshal(map[string]any{
		"engine":      args.Engine,
		"configPath":  args.ConfigPath,
		"tunStack":    stack,
		"tunMTU":      args.TunMTU,
		"tunMode":     bridge.TunModeAuto,
		"tlsFragment": args.TLSFragment,
	})
	if err != nil {
		return nil, &frameError{Code: "invalid_argument", Message: err.Error()}
	}
	if err := bridge.Start(string(options)); err != nil {
		return nil, &frameError{Code: "start_failed", Message: err.Error()}
	}
	return nil, nil
}

func decodeArgs(raw json.RawMessage, dst any) *frameError {
	if len(raw) == 0 {
		return nil
	}
	if err := json.Unmarshal(raw, dst); err != nil {
		return &frameError{Code: "invalid_argument", Message: err.Error()}
	}
	return nil
}
