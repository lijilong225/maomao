import 'dart:async';
import 'dart:io';

/// Measures how long a TCP handshake with a node's server takes.
///
/// While the core is down its own delay test is unreachable, and that test
/// sends an HTTP request *through* the proxy protocol, which the app cannot
/// speak. Reaching the endpoint directly is the most the app can do alone, so
/// the figure is a lower bound on the real latency and only proves the server
/// still accepts connections.
class LatencyProbe {
  const LatencyProbe({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  /// Round trip in milliseconds, or 0 when the server did not answer.
  Future<int> measure(String host, int port) async {
    final started = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final elapsed = started.elapsedMilliseconds;
      // A LAN node can answer inside a millisecond, and 0 reads as "untested".
      return elapsed > 0 ? elapsed : 1;
    } on SocketException {
      return 0;
    } on TimeoutException {
      return 0;
    } finally {
      socket?.destroy();
    }
  }
}
