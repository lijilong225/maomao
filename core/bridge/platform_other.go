//go:build !android

package bridge

import "context"

// withSingboxPlatform is a no-op off Android: desktop hosts let the core create
// and route the TUN interface itself, so there is no platform hook to install.
func withSingboxPlatform(ctx context.Context, opts startOptions) context.Context {
	return ctx
}

// releaseTunFD is a no-op off Android: no descriptor is handed over there.
func releaseTunFD(fd int) {}
