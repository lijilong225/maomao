import 'dart:async';

import 'package:flutter/services.dart';

import 'core_models.dart';

/// Raised when the platform rejects a core operation.
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

/// Talks to the embedded core through the platform channels registered by
/// `MaomaoPlugin`.
///
/// Only lifecycle and platform-only capabilities go through here. High-frequency
/// read-only data is served by the core's loopback RESTful controller.
class CoreChannel {
  CoreChannel({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methods = methodChannel ?? const MethodChannel(_methodChannelName),
      _events = eventChannel ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'com.maomao.proxy/core';
  static const _eventChannelName = 'com.maomao.proxy/core_events';

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<CoreEvent>? _eventStream;

  /// Broadcast so state and log consumers can subscribe independently.
  Stream<CoreEvent> get events {
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .map(_decodeEvent)
        .where((event) => event != null)
        .cast<CoreEvent>()
        .asBroadcastStream();
  }

  Stream<CoreState> get states => events
      .where((event) => event is CoreStateEvent)
      .cast<CoreStateEvent>()
      .map((event) => event.state);

  Stream<LogEntry> get logs => events
      .where((event) => event is CoreLogEvent)
      .cast<CoreLogEvent>()
      .map((event) => event.entry);

  Future<String> version() async => await _invoke<String>('version') ?? '';

  Future<CoreState> state() async =>
      CoreState.parse(await _invoke<String>('state') ?? '');

  Future<ControllerInfo> controllerInfo() async => ControllerInfo.fromMap(
    await _invoke<Map<dynamic, dynamic>>('controllerInfo'),
  );

  /// Shows the system VPN consent dialog when needed. Returns false if declined.
  Future<bool> prepareVpn() async => await _invoke<bool>('prepareVpn') ?? false;

  /// Throws [CoreException] carrying the core's own parse error message.
  Future<void> validateConfig(String configPath) =>
      _invoke<void>('validateConfig', {'configPath': configPath});

  /// Normalizes a raw subscription body (mihomo YAML or share links, optionally
  /// base64 encoded) into mihomo YAML using the core's own parsers.
  Future<String> convertSubscription(String raw) async =>
      await _invoke<String>('convertSubscription', {'raw': raw}) ?? '';

  /// Deep-merges a declarative YAML patch onto a base config.
  Future<String> mergeConfig(String base, String patch) async =>
      await _invoke<String>('mergeConfig', {'base': base, 'patch': patch}) ??
      '';

  Future<void> start(StartRequest request) =>
      _invoke<void>('start', request.toArguments());

  Future<void> stop() => _invoke<void>('stop');

  Future<Traffic> traffic() async =>
      Traffic.fromMap(await _invoke<Map<dynamic, dynamic>>('traffic'));

  Future<Traffic> trafficTotal() async =>
      Traffic.fromMap(await _invoke<Map<dynamic, dynamic>>('trafficTotal'));

  Future<List<InstalledApp>> installedApps() async {
    final raw = await _invoke<List<dynamic>>('installedApps') ?? const [];
    final apps = raw
        .whereType<Map<dynamic, dynamic>>()
        .map(InstalledApp.fromMap)
        .where((app) => app.packageName.isNotEmpty)
        .toList();
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw CoreException(e.code, e.message);
    } on MissingPluginException {
      throw CoreException('unsupported', 'Platform channel is unavailable');
    }
  }

  CoreEvent? _decodeEvent(dynamic raw) {
    if (raw is! Map) return null;
    return switch (raw['type']) {
      'state' => CoreStateEvent(CoreState.parse(raw['state'] as String? ?? '')),
      'log' => CoreLogEvent(
        LogEntry(
          level: LogLevel.parse(raw['level'] as String? ?? ''),
          payload: raw['payload'] as String? ?? '',
        ),
      ),
      _ => null,
    };
  }
}
