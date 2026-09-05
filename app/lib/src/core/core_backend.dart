import 'dart:async';

import 'core_models.dart';

/// Raised when the core backend rejects an operation.
class CoreException implements Exception {
  CoreException(this.code, this.message);

  final String code;
  final String? message;

  @override
  String toString() => message?.isNotEmpty == true ? message! : code;
}

sealed class CoreEvent {
  const CoreEvent();
}

class CoreStateEvent extends CoreEvent {
  const CoreStateEvent(this.state);

  final CoreState state;
}

class CoreLogEvent extends CoreEvent {
  const CoreLogEvent(this.entry);

  final LogEntry entry;
}

/// Lifecycle and platform-only capabilities of the embedded core.
///
/// Android links the core into the app process and reaches it over platform
/// channels; desktop hosts run it as a sidecar. High-frequency read-only data
/// never goes through here, it is served by the core's loopback controller.
abstract class CoreBackend {
  Stream<CoreEvent> get events;

  Stream<CoreState> get states => events
      .where((event) => event is CoreStateEvent)
      .cast<CoreStateEvent>()
      .map((event) => event.state);

  Stream<LogEntry> get logs => events
      .where((event) => event is CoreLogEvent)
      .cast<CoreLogEvent>()
      .map((event) => event.entry);

  Future<String> version();

  Future<CoreState> state();

  Future<ControllerInfo> controllerInfo();

  /// Shows the system VPN consent dialog when needed. Returns false if declined.
  Future<bool> prepareVpn();

  /// Throws [CoreException] carrying the core's own parse error message.
  Future<void> validateConfig(CoreEngine engine, String configPath);

  /// Normalizes a raw subscription body (mihomo YAML or share links, optionally
  /// base64 encoded) into mihomo YAML using the core's own parsers.
  Future<String> convertSubscription(String raw);

  /// Deep-merges a declarative YAML patch onto a base config.
  Future<String> mergeConfig(String base, String patch);

  /// Translates a mihomo YAML config into a sing-box JSON config.
  Future<String> convertToSingbox(String yaml);

  Future<void> start(StartRequest request);

  Future<void> stop();

  Future<Traffic> traffic();

  Future<Traffic> trafficTotal();

  /// Empty where per-app proxying is not a platform capability.
  Future<List<InstalledApp>> installedApps();

  Future<void> dispose();
}

/// Shared decoding of the `state` and `log` frames every backend emits.
CoreEvent? decodeCoreEvent(Map<dynamic, dynamic> raw) => switch (raw['type']) {
  'state' => CoreStateEvent(CoreState.parse(raw['state'] as String? ?? '')),
  'log' => CoreLogEvent(
    LogEntry(
      level: LogLevel.parse(raw['level'] as String? ?? ''),
      payload: raw['payload'] as String? ?? '',
    ),
  ),
  _ => null,
};
