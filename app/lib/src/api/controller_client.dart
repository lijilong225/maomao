import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/core_models.dart';
import 'controller_models.dart';

/// Raised when the controller returns a non-success status.
class ControllerException implements Exception {
  ControllerException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  @override
  String toString() => 'ControllerException($statusCode): $message';
}

/// Client for the core's External Controller.
///
/// The controller is bound to `127.0.0.1` on a host-allocated random port with a
/// per-launch random secret, so traffic never leaves the device. All high
/// frequency read-only data (proxies, connections, logs, traffic) is served here
/// instead of crossing the platform channel.
class ControllerClient {
  ControllerClient(this._info, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'http://${_info.addr}',
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Authorization': 'Bearer ${_info.secret}'},
              responseType: ResponseType.json,
            ),
          );

  final ControllerInfo _info;
  final Dio _dio;

  static const defaultDelayTestUrl = 'https://www.gstatic.com/generate_204';

  void close() => _dio.close(force: true);

  // ---------------------------------------------------------------- proxies

  /// All proxies and groups keyed by name.
  Future<Map<String, ProxyNode>> proxies() async {
    final data = await _get<Map<String, dynamic>>('/proxies');
    final raw = (data['proxies'] as Map<String, dynamic>?) ?? const {};
    return raw.map(
      (name, value) => MapEntry(
        name,
        ProxyNode.fromJson(name, (value as Map).cast<String, dynamic>()),
      ),
    );
  }

  Future<ProxyNode> proxy(String name) async {
    final data = await _get<Map<String, dynamic>>('/proxies/${_seg(name)}');
    return ProxyNode.fromJson(name, data);
  }

  /// Nodes grouped by the provider that owns them.
  ///
  /// Nodes coming from `proxy-providers` never show up in [proxies], so their
  /// latency history is only reachable here. The reserved `default` provider
  /// lists everything declared inline in the config file, in config file order.
  Future<Map<String, List<ProxyNode>>> providerProxies() async {
    final data = await _get<Map<String, dynamic>>('/providers/proxies');
    final raw = (data['providers'] as Map<String, dynamic>?) ?? const {};
    return raw.map((name, value) {
      final members = ((value as Map)['proxies'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((json) => ProxyNode.fromJson(json['name'] as String? ?? '', json))
          .toList();
      return MapEntry(name, members);
    });
  }

  /// Merged view of [proxies] and [providerProxies].
  Future<ProxySnapshot> snapshot() async {
    final results = await Future.wait([proxies(), providerProxies()]);
    return ProxySnapshot.merge(
      proxies: results[0] as Map<String, ProxyNode>,
      providers: results[1] as Map<String, List<ProxyNode>>,
    );
  }

  /// Switches the member selected by a `Selector` group.
  Future<void> selectProxy(String groupName, String memberName) =>
      _request<void>(
        'PUT',
        '/proxies/${_seg(groupName)}',
        data: {'name': memberName},
      );

  /// Latency of a single node in milliseconds.
  Future<int> proxyDelay(
    String name, {
    String url = defaultDelayTestUrl,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final data = await _get<Map<String, dynamic>>(
      '/proxies/${_seg(name)}/delay',
      query: {'url': url, 'timeout': timeout.inMilliseconds},
    );
    return (data['delay'] as num?)?.toInt() ?? 0;
  }

  /// Latency of every member of a group, keyed by member name.
  Future<Map<String, int>> groupDelay(
    String groupName, {
    String url = defaultDelayTestUrl,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final data = await _get<Map<String, dynamic>>(
      '/group/${_seg(groupName)}/delay',
      query: {'url': url, 'timeout': timeout.inMilliseconds},
    );
    return data.map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0));
  }

  // ------------------------------------------------------------------ rules

  Future<List<RuleItem>> rules() async {
    final data = await _get<Map<String, dynamic>>('/rules');
    return (data['rules'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RuleItem.fromJson)
        .toList();
  }

  // -------------------------------------------------------------- providers

  /// Entries declared under `proxy-providers:`.
  ///
  /// The core also reports synthesized `Compatible` providers that merely hold
  /// the proxies written inline in the config file; those are dropped.
  Future<List<ProxyProviderInfo>> proxyProviders() async {
    final data = await _get<Map<String, dynamic>>('/providers/proxies');
    final raw = (data['providers'] as Map<String, dynamic>?) ?? const {};
    return [
      for (final entry in raw.entries)
        if (entry.value is Map)
          ProxyProviderInfo.fromJson(
            entry.key,
            (entry.value as Map).cast<String, dynamic>(),
          ),
    ]
      ..removeWhere((provider) => provider.vehicleType == 'Compatible')
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<RuleProviderInfo>> ruleProviders() async {
    final data = await _get<Map<String, dynamic>>('/providers/rules');
    final raw = (data['providers'] as Map<String, dynamic>?) ?? const {};
    return [
      for (final entry in raw.entries)
        if (entry.value is Map)
          RuleProviderInfo.fromJson(
            entry.key,
            (entry.value as Map).cast<String, dynamic>(),
          ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Re-downloads a `proxy-providers` entry.
  Future<void> updateProxyProvider(String name) =>
      _request<void>('PUT', '/providers/proxies/${_seg(name)}');

  /// Re-downloads a `rule-providers` entry.
  Future<void> updateRuleProvider(String name) =>
      _request<void>('PUT', '/providers/rules/${_seg(name)}');

  // ------------------------------------------------------------ connections

  Future<ConnectionSnapshot> connections() async {
    final data = await _get<Map<String, dynamic>>('/connections');
    return ConnectionSnapshot.fromJson(data);
  }

  Future<void> closeConnection(String id) =>
      _request<void>('DELETE', '/connections/${_seg(id)}');

  Future<void> closeAllConnections() => _request<void>('DELETE', '/connections');

  // ---------------------------------------------------------------- configs

  Future<Map<String, dynamic>> configs() =>
      _get<Map<String, dynamic>>('/configs');

  Future<String> version() async {
    final data = await _get<Map<String, dynamic>>('/version');
    return data['version'] as String? ?? '';
  }

  /// Re-downloads every enabled geo database; the core has no per-file call.
  Future<void> updateGeoDatabases() => _request<void>('POST', '/configs/geo');

  // ------------------------------------------------------------- WS streams

  /// Live traffic samples, one per second.
  Stream<Traffic> trafficStream() =>
      _wsStream('/traffic').map((json) => Traffic.fromMap(json));

  Stream<MemoryUsage> memoryStream() =>
      _wsStream('/memory').map(MemoryUsage.fromJson);

  Stream<LogEntry> logStream({LogLevel level = LogLevel.info}) => _wsStream(
    '/logs',
    query: {'level': level.name},
  ).map(
    (json) => LogEntry(
      level: LogLevel.parse(json['type'] as String? ?? ''),
      payload: json['payload'] as String? ?? '',
    ),
  );

  Stream<ConnectionSnapshot> connectionStream() =>
      _wsStream('/connections').map(ConnectionSnapshot.fromJson);

  /// The controller accepts the secret as a `token` query parameter for
  /// websocket upgrades, since browsers cannot set custom headers there.
  Stream<Map<String, dynamic>> _wsStream(
    String path, {
    Map<String, dynamic>? query,
  }) {
    final uri = Uri.parse('ws://${_info.addr}$path').replace(
      queryParameters: {
        ...?query?.map((k, v) => MapEntry(k, '$v')),
        'token': _info.secret,
      },
    );

    late StreamController<Map<String, dynamic>> controller;
    WebSocketChannel? channel;

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        channel = WebSocketChannel.connect(uri);
        channel!.stream.listen(
          (raw) {
            if (raw is! String) return;
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map<String, dynamic>) controller.add(decoded);
            } on FormatException {
              // Ignore malformed frames rather than tearing down the stream.
            }
          },
          onError: controller.addError,
          onDone: controller.close,
          cancelOnError: true,
        );
      },
      onCancel: () async {
        await channel?.sink.close();
      },
    );

    return controller.stream;
  }

  // ----------------------------------------------------------------- plumbing

  static String _seg(String value) => Uri.encodeComponent(value);

  Future<T> _get<T>(String path, {Map<String, dynamic>? query}) async {
    final result = await _request<T>('GET', path, query: query);
    if (result == null) {
      throw ControllerException(null, 'Empty response for $path');
    }
    return result;
  }

  Future<T?> _request<T>(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    try {
      final response = await _dio.request<T>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
      return response.data;
    } on DioException catch (e) {
      throw ControllerException(
        e.response?.statusCode,
        _describe(e),
      );
    }
  }

  static String _describe(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['message'] is String) return body['message'] as String;
    return e.message ?? e.type.name;
  }
}
