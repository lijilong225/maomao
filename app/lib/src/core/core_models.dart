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

/// Options handed to the platform when starting the tunnel.
class StartRequest {
  const StartRequest({
    required this.configPath,
    this.profileName = 'maomao',
    this.tunStack = TunStack.gvisor,
    this.allowedApps = const [],
    this.disallowedApps = const [],
    this.ipv6 = false,
    this.bypassPrivateRoutes = true,
  });

  final String configPath;
  final String profileName;
  final TunStack tunStack;
  final List<String> allowedApps;
  final List<String> disallowedApps;
  final bool ipv6;
  final bool bypassPrivateRoutes;

  Map<String, dynamic> toArguments() => {
    'configPath': configPath,
    'profileName': profileName,
    'tunStack': tunStack.wireName,
    'allowedApps': allowedApps,
    'disallowedApps': disallowedApps,
    'ipv6': ipv6,
    'bypassPrivateRoutes': bypassPrivateRoutes,
  };

  @override
  String toString() => jsonEncode(toArguments());
}

/// Options for measuring node delay while the tunnel is down.
class DelayProbeRequest {
  const DelayProbeRequest({
    required this.configYaml,
    this.providerBodies = const {},
    this.names = const [],
    this.timeout = const Duration(seconds: 5),
    this.concurrency = 8,
  });

  final String configYaml;

  /// Cached proxy-provider bodies keyed by provider name, so nodes that do not
  /// live in the config itself can be measured too.
  final Map<String, String> providerBodies;

  /// Empty measures every node the config and the providers describe.
  final List<String> names;
  final Duration timeout;
  final int concurrency;

  /// The core takes the whole request as one JSON string, because gomobile only
  /// binds basic types.
  String toWireJson() => jsonEncode({
    'configYaml': configYaml,
    'providerBodies': providerBodies,
    'names': names,
    'timeoutMs': timeout.inMilliseconds,
    'concurrency': concurrency,
  });

  Map<String, dynamic> toArguments() => {'request': toWireJson()};
}

/// Reads the core's probe reply, dropping anything it does not recognise.
Map<String, int> decodeDelayProbe(Map<dynamic, dynamic>? raw) {
  final delays = raw?['delays'];
  if (delays is! Map) return const {};
  return {
    for (final entry in delays.entries)
      if (entry.key is String && entry.value is num)
        entry.key as String: (entry.value as num).toInt(),
  };
}
