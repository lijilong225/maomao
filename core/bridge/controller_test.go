package bridge

import (
	"net"
	"testing"
	"time"

	"github.com/metacubex/mihomo/hub/route"
)

// TestMihomoShutdownReleasesControllerAddress guards the handover between cores.
//
// The controller address is allocated once and handed to whichever core is
// running, so a core that keeps its listener after being shut down makes its
// successor fail to bind. mihomo is the case that bites: its RESTful controller
// is a package global in hub/route and survives executor.Shutdown.
func TestMihomoShutdownReleasesControllerAddress(t *testing.T) {
	addr, _, err := allocController()
	if err != nil {
		t.Fatalf("allocate controller address: %v", err)
	}
	useControllerAddr(t, addr)

	route.ReCreateServer(&route.Config{Addr: addr})
	// Leaving a listener behind would break whatever test runs next.
	t.Cleanup(func() { route.ReCreateServer(&route.Config{}) })
	waitControllerUp(t, addr)

	engine := &mihomoEngine{}
	engine.shutdown()

	l, err := net.Listen("tcp", addr)
	if err != nil {
		t.Fatalf("controller address still bound after shutdown: %v", err)
	}
	_ = l.Close()
}

// TestAwaitControllerReleaseGivesUp keeps a stuck listener from wedging the host:
// shutdown runs on the Android service's single worker thread, so waiting there
// without a bound would freeze every later tunnel operation.
func TestAwaitControllerReleaseGivesUp(t *testing.T) {
	addr, _, err := allocController()
	if err != nil {
		t.Fatalf("allocate controller address: %v", err)
	}
	holder, err := net.Listen("tcp", addr)
	if err != nil {
		t.Fatalf("hold controller address: %v", err)
	}
	defer holder.Close()
	useControllerAddr(t, addr)

	done := make(chan struct{})
	go func() {
		awaitControllerRelease()
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(10 * controllerReleaseTimeout):
		t.Fatal("wait for the controller address never gave up")
	}
}

// useControllerAddr points the bridge at addr for the duration of the test.
func useControllerAddr(t *testing.T, addr string) {
	t.Helper()
	mu.Lock()
	previous := controller
	controller = controllerInfo{Addr: addr}
	mu.Unlock()

	t.Cleanup(func() {
		mu.Lock()
		controller = previous
		mu.Unlock()
	})
}

// waitControllerUp blocks until addr accepts connections. mihomo binds it from a
// goroutine, so the address is not taken the moment ReCreateServer returns.
//
// Dialling rather than listening on purpose: a probe that binds the address would
// race the core for it and could be the reason the core fails to come up.
func waitControllerUp(t *testing.T, addr string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		conn, err := net.Dial("tcp", addr)
		if err == nil {
			_ = conn.Close()
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("controller never came up at %s", addr)
}
