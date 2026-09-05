//go:build !android

package bridge

// installXrayDialerHook is a no-op outside Android; desktop platforms rely on routing.
func installXrayDialerHook() {}
