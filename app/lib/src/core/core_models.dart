import 'dart:convert';

/// Lifecycle states reported by the core.
enum CoreState {
  stopped,
  starting,
  running;

  static CoreState parse(String raw) => switch (raw) {
    'starting' => CoreState.starting,
    'running' => CoreState.running,
    _ => CoreState.stopped,
  };

  bool get isActive => this != CoreState.stopped;
}

/// Endpoint of the core's loopback RESTful controller.
///
/// The secret is regenerated on every start and never persisted.
class ControllerInfo {
  const ControllerInfo({required this.addr, required this.secret});

  final String addr;
  final String secret;

  bool get isReady => addr.isNotEmpty && secret.isNotEmpty;

  Uri httpUri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('http://$addr$path').replace(queryParameters: query);

  Uri wsUri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('ws://$addr$path').replace(queryParameters: query);

  Map<String, String> get authHeaders => {'Authorization': 'Bearer $secret'};

  static ControllerInfo fromMap(Map<dynamic, dynamic>? map) => ControllerInfo(
    addr: map?['addr'] as String? ?? '',
    secret: map?['secret'] as String? ?? '',
  );
}

class Traffic {
  const Traffic({required this.up, required this.down});

  const Traffic.zero() : up = 0, down = 0;

  final int up;
  final int down;

  static Traffic fromMap(Map<dynamic, dynamic>? map) => Traffic(
    up: (map?['up'] as num?)?.toInt() ?? 0,
    down: (map?['down'] as num?)?.toInt() ?? 0,
  );
}

enum LogLevel {
  debug,
  info,
  warning,
  error;

  static LogLevel parse(String raw) => switch (raw) {
    'debug' => LogLevel.debug,
    'warning' => LogLevel.warning,
    'error' => LogLevel.error,
    _ => LogLevel.info,
  };
}

class LogEntry {
  LogEntry({required this.level, required this.payload, DateTime? time})
    : time = time ?? DateTime.now();

  final LogLevel level;
  final String payload;
  final DateTime time;
}

/// An app installed on the device, used by the per-app proxy picker.
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    required this.isSystem,
  });

  final String packageName;
  final String label;
  final bool isSystem;

  static InstalledApp fromMap(Map<dynamic, dynamic> map) => InstalledApp(
    packageName: map['packageName'] as String? ?? '',
    label: map['label'] as String? ?? '',
    isSystem: map['system'] as bool? ?? false,
  );
}

/// TUN stacks supported by the core.
enum TunStack {
  gvisor,
  system,
  mixed;

  String get wireName => name;
}

/// Proxy engines embedded in the core. Only one can run at a time.
enum ProxyKernel {
  mihomo,
  xray;

  String get wireName => name;

  static ProxyKernel parse(String raw) => switch (raw) {
    'xray' => ProxyKernel.xray,
    _ => ProxyKernel.mihomo,
  };
}

/// Options handed to the platform when starting the tunnel.
class StartRequest {
  const StartRequest({
    required this.configPath,
    this.profileName = 'maomao',
    this.kernel = ProxyKernel.mihomo,
    this.tunStack = TunStack.gvisor,
    this.allowedApps = const [],
    this.disallowedApps = const [],
    this.ipv6 = false,
    this.bypassPrivateRoutes = true,
    this.xrayFragment = false,
  });

  final String configPath;
  final String profileName;
  final ProxyKernel kernel;
  final TunStack tunStack;
  final List<String> allowedApps;
  final List<String> disallowedApps;
  final bool ipv6;
  final bool bypassPrivateRoutes;
  final bool xrayFragment;

  Map<String, dynamic> toArguments() => {
    'configPath': configPath,
    'profileName': profileName,
    'kernel': kernel.wireName,
    'tunStack': tunStack.wireName,
    'allowedApps': allowedApps,
    'disallowedApps': disallowedApps,
    'ipv6': ipv6,
    'bypassPrivateRoutes': bypassPrivateRoutes,
    'xrayFragment': xrayFragment,
  };

  @override
  String toString() => jsonEncode(toArguments());
}
