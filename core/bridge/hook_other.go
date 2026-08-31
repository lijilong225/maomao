//go:build !android

package bridge

// installSocketHook is a no-op outside Android; desktop platforms rely on routing.
func installSocketHook() {}
