import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'core_backend.dart';
import 'core_models.dart';

/// Talks to the in-process core through the platform channels registered by
/// `MaomaoPlugin`.
class CoreChannel extends CoreBackend {
  CoreChannel({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methods = methodChannel ?? const MethodChannel(_methodChannelName),
      _events = eventChannel ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'com.maomao.proxy/core';
  static const _eventChannelName = 'com.maomao.proxy/core_events';

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<CoreEvent>? _eventStream;

  /// Broadcast so state and log consumers can subscribe independently.
  @override
  Stream<CoreEvent> get events {
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .map(_decodeEvent)
        .where((event) => event != null)
        .cast<CoreEvent>()
        .asBroadcastStream();
  }

  @override
  Future<String> version() async => await _invoke<String>('version') ?? '';

  @override
  Future<CoreState> state() async =>
      CoreState.parse(await _invoke<String>('state') ?? '');

  @override
  Future<ControllerInfo> controllerInfo() async => ControllerInfo.fromMap(
    await _invoke<Map<dynamic, dynamic>>('controllerInfo'),
  );

  /// Shows the system VPN consent dialog when needed. Returns false if declined.
  @override
  Future<bool> prepareVpn() async => await _invoke<bool>('prepareVpn') ?? false;

  @override
  Future<void> validateConfig(String configPath) =>
      _invoke<void>('validateConfig', {'configPath': configPath});

  @override
  Future<String> convertSubscription(String raw) async =>
      await _invoke<String>('convertSubscription', {'raw': raw}) ?? '';

  @override
  Future<String> mergeConfig(String base, String patch) async =>
      await _invoke<String>('mergeConfig', {'base': base, 'patch': patch}) ??
      '';

  @override
  Future<void> start(StartRequest request) =>
      _invoke<void>('start', request.toArguments());

  @override
  Future<void> stop() => _invoke<void>('stop');

  @override
  Future<Traffic> traffic() async =>
      Traffic.fromMap(await _invoke<Map<dynamic, dynamic>>('traffic'));

  @override
  Future<Traffic> trafficTotal() async =>
      Traffic.fromMap(await _invoke<Map<dynamic, dynamic>>('trafficTotal'));

  @override
  Future<Map<String, int>> probeDelay(DelayProbeRequest request) async {
    final raw = await _invoke<String>('probeDelay', request.toArguments());
    if (raw == null || raw.isEmpty) return const {};
    return decodeDelayProbe(jsonDecode(raw) as Map<dynamic, dynamic>);
  }

  @override
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

  /// The core lives in the app process here, so there is nothing to tear down.
  @override
  Future<void> dispose() async {}

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

  CoreEvent? _decodeEvent(dynamic raw) =>
      raw is Map ? decodeCoreEvent(raw) : null;
}
