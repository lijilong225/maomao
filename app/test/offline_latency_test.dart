import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/api/controller_models.dart';
import 'package:maomao/src/core/core_backend.dart';
import 'package:maomao/src/core/core_models.dart';
import 'package:maomao/src/core/core_service.dart';
import 'package:maomao/src/profile/latency_probe.dart';
import 'package:maomao/src/profile/profile_providers.dart';

void main() {
  ProxyNode node(String name, {String? server, int? port}) => ProxyNode(
    name: name,
    type: 'Shadowsocks',
    udp: false,
    history: const [],
    server: server,
    port: port,
  );

  test('reports the delays the core measured', () async {
    final backend = _FakeBackend(delays: {'a': 120, 'b': 0});
    final controller = _controller(backend);

    await controller.measureAll([
      node('a', server: '1.1.1.1', port: 443),
      node('b', server: '1.0.0.1', port: 443),
    ]);

    expect(controller.state, {'a': 120, 'b': 0});
    expect(backend.requests.single.names, ['a', 'b']);
  });

  test('passes the active profile and its cached providers to the core', () async {
    final backend = _FakeBackend(delays: {'a': 1});
    final controller = _controller(backend);

    await controller.measureAll([node('a', server: '1.1.1.1', port: 443)]);

    final request = backend.requests.single;
    expect(request.configYaml, _configYaml);
    expect(request.providerBodies, {'remote': _providerYaml});
  });

  test('skips nodes the app cannot dial on its own', () async {
    final backend = _FakeBackend(delays: {});
    final controller = _controller(backend);

    await controller.measureAll([node('group'), node('a', server: '')]);

    expect(backend.requests, isEmpty);
    expect(controller.state, isEmpty);
  });

  test('falls back to a handshake for nodes the core did not report', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) => socket.destroy());

    final backend = _FakeBackend(delays: {'measured': 90});
    final controller = _controller(backend);

    await controller.measureAll([
      node('measured', server: '1.1.1.1', port: 443),
      node('exotic', server: '127.0.0.1', port: server.port),
    ]);

    expect(controller.state['measured'], 90);
    expect(controller.state['exotic'], greaterThan(0));
  });

  test('falls back to a handshake when the core rejects the probe', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) => socket.destroy());

    final backend = _FakeBackend(delays: {}, failure: CoreException('boom', ''));
    final controller = _controller(backend);

    await controller.measureAll([
      node('a', server: '127.0.0.1', port: server.port),
    ]);

    expect(controller.state['a'], greaterThan(0));
  });
}

const _configYaml = 'proxies:\n  - name: a\n';
const _providerYaml = 'proxies:\n  - name: b\n';

OfflineLatencyController _controller(_FakeBackend backend) =>
    OfflineLatencyController(
      probe: const LatencyProbe(timeout: Duration(seconds: 2)),
      core: CoreService(channel: backend),
      loadSource: () async =>
          (configYaml: _configYaml, providerBodies: {'remote': _providerYaml}),
    );

class _FakeBackend extends CoreBackend {
  _FakeBackend({required this.delays, this.failure});

  final Map<String, int> delays;
  final CoreException? failure;
  final requests = <DelayProbeRequest>[];

  @override
  Stream<CoreEvent> get events => const Stream.empty();

  @override
  Future<Map<String, int>> probeDelay(DelayProbeRequest request) async {
    requests.add(request);
    final error = failure;
    if (error != null) throw error;
    return delays;
  }

  @override
  Future<String> version() async => '';

  @override
  Future<CoreState> state() async => CoreState.stopped;

  @override
  Future<ControllerInfo> controllerInfo() async =>
      const ControllerInfo(addr: '', secret: '');

  @override
  Future<bool> prepareVpn() async => true;

  @override
  Future<void> validateConfig(String configPath) async {}

  @override
  Future<String> convertSubscription(String raw) async => raw;

  @override
  Future<String> mergeConfig(String base, String patch) async => base;

  @override
  Future<void> start(StartRequest request) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<Traffic> traffic() async => Traffic.zero();

  @override
  Future<Traffic> trafficTotal() async => Traffic.zero();

  @override
  Future<List<InstalledApp>> installedApps() async => const [];

  @override
  Future<void> dispose() async {}
}
