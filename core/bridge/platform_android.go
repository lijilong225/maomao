//go:build android

package bridge

import (
	"context"
	"fmt"
	"net/netip"
	"os"
	"sync"
	"syscall"
	"unsafe"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/control"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/common/x/list"
	"github.com/sagernet/sing/service"
	"golang.org/x/sys/unix"
)

// withSingboxPlatform injects the Android platform hooks sing-box needs to bind
// the descriptor produced by VpnService.establish() and to keep its own sockets
// outside the tunnel.
//
// Without a descriptor there is nothing to adopt, so the core is left to open its
// own interface, which is what config validation does.
func withSingboxPlatform(ctx context.Context, opts startOptions) context.Context {
	if opts.TunFd <= 0 {
		return ctx
	}
	return service.ContextWith[adapter.PlatformInterface](ctx, &androidPlatform{tunFd: opts.TunFd})
}

// androidPlatform implements the handful of adapter.PlatformInterface methods
// that matter on Android; everything else reports "not provided" so sing-box
// keeps using its own implementation.
type androidPlatform struct {
	tunFd   int
	monitor *androidInterfaceMonitor
}

func (p *androidPlatform) Initialize(networkManager adapter.NetworkManager) error {
	return nil
}

// Sockets opened by the core must bypass the tunnel, or its own traffic would be
// routed back into itself.
func (p *androidPlatform) UsePlatformAutoDetectInterfaceControl() bool { return true }

func (p *androidPlatform) AutoDetectInterfaceControl(fd int) error {
	mu.Lock()
	d := delegate
	mu.Unlock()

	if d == nil {
		return nil
	}
	if !d.Protect(int32(fd)) {
		return fmt.Errorf("protect socket %d failed", fd)
	}
	return nil
}

// The descriptor comes from VpnService, so the core must adopt it rather than
// create an interface of its own.
func (p *androidPlatform) UsePlatformInterface() bool { return true }

func (p *androidPlatform) OpenInterface(options *tun.Options, platformOptions option.TunPlatformOptions) (tun.Tun, error) {
	// The descriptor is duplicated because sing-box closes what it is handed, and
	// the host keeps its own copy alive for the lifetime of the service.
	dupFd, err := syscall.Dup(p.tunFd)
	if err != nil {
		return nil, fmt.Errorf("dup tun fd: %w", err)
	}

	options.FileDescriptor = dupFd
	name, err := androidTunnelName(int32(dupFd))
	if err != nil {
		// Only the interface name is lost, and it is used for logging and for the
		// direct outbound's own-address filter, so a fallback is preferable to
		// failing the whole tunnel.
		name = "tun0"
	}
	options.Name = name
	if options.InterfaceMonitor != nil {
		options.InterfaceMonitor.RegisterMyInterface(name)
	}

	tunInterface, err := tun.New(*options)
	if err != nil {
		_ = syscall.Close(dupFd)
		return nil, err
	}
	return tunInterface, nil
}

func (p *androidPlatform) ProcessPlatformOptions(options option.TunPlatformOptions) error {
	return nil
}

// sing-box would otherwise open a netlink socket to watch for route changes,
// which the Android sandbox forbids for unprivileged apps.
func (p *androidPlatform) UsePlatformDefaultInterfaceMonitor() bool { return true }

func (p *androidPlatform) CreateDefaultInterfaceMonitor(logger logger.Logger) tun.DefaultInterfaceMonitor {
	if p.monitor == nil {
		p.monitor = &androidInterfaceMonitor{}
	}
	return p.monitor
}

// Returning false keeps sing-box on its own interface enumeration, which works
// from inside the sandbox because it only reads the local interface list.
func (p *androidPlatform) UsePlatformNetworkInterfaces() bool { return false }

func (p *androidPlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) {
	return nil, os.ErrInvalid
}

func (p *androidPlatform) UnderNetworkExtension() bool { return false }

func (p *androidPlatform) NetworkExtensionIncludeAllNetworks() bool { return false }

func (p *androidPlatform) ClearDNSCache() {}

func (p *androidPlatform) RequestPermissionForWIFIState() error { return nil }

func (p *androidPlatform) ReadWIFIState(ctx context.Context) adapter.WIFIState {
	return adapter.WIFIState{}
}

func (p *androidPlatform) UsePlatformConnectionOwnerFinder() bool { return false }

func (p *androidPlatform) FindConnectionOwner(request *adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return nil, os.ErrInvalid
}

func (p *androidPlatform) UsePlatformWIFIMonitor() bool { return false }

func (p *androidPlatform) UsePlatformNotification() bool { return false }

func (p *androidPlatform) SendNotification(notification *adapter.Notification) error {
	return os.ErrInvalid
}

func (p *androidPlatform) CancelNotification(identifier string, typeID int32) error { return nil }

func (p *androidPlatform) MyInterfaceAddress() []netip.Addr { return nil }

func (p *androidPlatform) UsePlatformNeighborResolver() bool { return false }

func (p *androidPlatform) StartNeighborMonitor(listener adapter.NeighborUpdateListener) error {
	return os.ErrInvalid
}

func (p *androidPlatform) CloseNeighborMonitor(listener adapter.NeighborUpdateListener) error {
	return nil
}

func (p *androidPlatform) UsePlatformShell() bool { return false }

func (p *androidPlatform) CheckPlatformShell() error { return nil }

func (p *androidPlatform) OpenShellSession(user *adapter.PlatformUser, command string, env []string, term string, rows int32, cols int32) (adapter.ShellSession, error) {
	return nil, os.ErrInvalid
}

func (p *androidPlatform) LookupUser(username string) (*adapter.PlatformUser, error) {
	return nil, os.ErrInvalid
}

func (p *androidPlatform) LookupSFTPServer() (string, error) { return "", os.ErrInvalid }

func (p *androidPlatform) ReadSystemSSHHostKey() ([]byte, error) { return nil, os.ErrInvalid }

func (p *androidPlatform) TailscaleHostname() string { return "" }

func (p *androidPlatform) UsePlatformBridge() bool { return false }

func (p *androidPlatform) CreateBridge(options adapter.BridgeOptions) (adapter.BridgeSession, error) {
	return nil, os.ErrInvalid
}

// androidInterfaceMonitor stands in for the netlink-backed monitor sing-box
// cannot use here.
//
// The app rebuilds the tunnel whenever connectivity changes, so nothing has to be
// observed: it only needs to record the TUN interface name and never report a
// default interface, which callers already treat as "unknown".
type androidInterfaceMonitor struct {
	access       sync.Mutex
	callbacks    list.List[tun.DefaultInterfaceUpdateCallback]
	myInterfaces []string
}

func (m *androidInterfaceMonitor) Start() error { return nil }

func (m *androidInterfaceMonitor) Close() error { return nil }

func (m *androidInterfaceMonitor) DefaultInterface() *control.Interface { return nil }

func (m *androidInterfaceMonitor) OverrideAndroidVPN() bool { return false }

func (m *androidInterfaceMonitor) AndroidVPNEnabled() bool { return false }

func (m *androidInterfaceMonitor) RegisterCallback(callback tun.DefaultInterfaceUpdateCallback) *list.Element[tun.DefaultInterfaceUpdateCallback] {
	m.access.Lock()
	defer m.access.Unlock()
	return m.callbacks.PushBack(callback)
}

func (m *androidInterfaceMonitor) UnregisterCallback(element *list.Element[tun.DefaultInterfaceUpdateCallback]) {
	m.access.Lock()
	defer m.access.Unlock()
	m.callbacks.Remove(element)
}

func (m *androidInterfaceMonitor) RegisterMyInterface(interfaceName string) {
	m.access.Lock()
	defer m.access.Unlock()
	for _, name := range m.myInterfaces {
		if name == interfaceName {
			return
		}
	}
	m.myInterfaces = append(m.myInterfaces, interfaceName)
}

func (m *androidInterfaceMonitor) MyInterfaces() []string {
	m.access.Lock()
	defer m.access.Unlock()
	return append([]string(nil), m.myInterfaces...)
}

const androidIfReqSize = unix.IFNAMSIZ + 64

// androidTunnelName recovers the interface name of a TUN descriptor. The Android
// VpnService API never reveals it, so it has to be asked for directly.
func androidTunnelName(fd int32) (string, error) {
	var ifr [androidIfReqSize]byte
	_, _, errno := unix.Syscall(
		unix.SYS_IOCTL,
		uintptr(fd),
		uintptr(unix.TUNGETIFF),
		uintptr(unsafe.Pointer(&ifr[0])),
	)
	if errno != 0 {
		return "", fmt.Errorf("get tun name: %w", errno)
	}
	return unix.ByteSliceToString(ifr[:]), nil
}
