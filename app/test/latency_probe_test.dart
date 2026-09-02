import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/profile/latency_probe.dart';

void main() {
  test('times a reachable server', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) => socket.destroy());

    final delay = await const LatencyProbe().measure('127.0.0.1', server.port);

    // A loopback handshake can finish inside a millisecond, but 0 is reserved
    // for failures.
    expect(delay, greaterThan(0));
  });

  test('reports zero when nothing listens', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();

    final delay = await const LatencyProbe(timeout: Duration(seconds: 2))
        .measure('127.0.0.1', port);

    expect(delay, 0);
  });
}
