//go:build android

package bridge

import (
	"errors"
	"sync"
	"syscall"

	"github.com/xtls/xray-core/transport/internet"
)

var xrayDialerHookOnce sync.Once

// installXrayDialerHook routes every outbound socket through VpnService.protect so
// the core's own traffic is not captured by the tunnel it created. Controllers
// accumulate on xray's shared dialer, so this may only run once per process.
func installXrayDialerHook() {
	xrayDialerHookOnce.Do(func() {
		_ = internet.RegisterDialerController(func(network, address string, conn syscall.RawConn) error {
			mu.Lock()
			d := delegate
			mu.Unlock()
			if d == nil {
				return nil
			}

			var protectErr error
			err := conn.Control(func(fd uintptr) {
				if !d.Protect(int32(fd)) {
					protectErr = errors.New("protect socket failed")
				}
			})
			if err != nil {
				return err
			}
			return protectErr
		})
	})
}
