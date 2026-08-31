//go:build android

package bridge

import (
	"errors"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
)

// installSocketHook routes every outbound socket through VpnService.protect so the
// core's own traffic is not captured by the tunnel it created.
func installSocketHook() {
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
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
	}
}
