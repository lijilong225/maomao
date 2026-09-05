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

/// Proxy cores bundled with the app.
///
/// Profiles are always authored in the mihomo format; the sing-box engine runs
/// on a config translated by the core, so switching engines does not require
/// re-importing a subscription.
enum CoreEngine {
  mihomo,
  singbox;

  String get wireName => name;

  /// Whether the engine exposes mihomo's provider and geo database endpoints.
  bool get supportsProviders => this == CoreEngine.mihomo;

  /// Whether the controller can pin a member of an automatic group. sing-box
  /// only switches selector groups, so the core publishes every automatic group
  /// behind one and whatever still reports `URLTest` stays read-only.
  bool get switchesAutomaticGroups => this == CoreEngine.mihomo;

  static CoreEngine parse(String? raw) => switch (raw) {
    'singbox' => CoreEngine.singbox,
    _ => CoreEngine.mihomo,
  };
}

/// Options handed to the platform when starting the tunnel.
class StartRequest {
  const StartRequest({
    required this.configPath,
    this.engine = CoreEngine.mihomo,
    this.profileName = 'maomao',
    this.tunStack = TunStack.gvisor,
    this.allowedApps = const [],
    this.disallowedApps = const [],
    this.ipv6 = false,
    this.bypassPrivateRoutes = true,
    this.tlsFragment = false,
  });

  final String configPath;
  final CoreEngine engine;
  final String profileName;
  final TunStack tunStack;
  final List<String> allowedApps;
  final List<String> disallowedApps;
  final bool ipv6;
  final bool bypassPrivateRoutes;

  /// Fragments the TLS handshake. Ignored by the mihomo core.
  final bool tlsFragment;

  Map<String, dynamic> toArguments() => {
    'engine': engine.wireName,
    'configPath': configPath,
    'profileName': profileName,
    'tunStack': tunStack.wireName,
    'allowedApps': allowedApps,
    'disallowedApps': disallowedApps,
    'ipv6': ipv6,
    'bypassPrivateRoutes': bypassPrivateRoutes,
    'tlsFragment': tlsFragment,
  };

  @override
  String toString() => jsonEncode(toArguments());
}
