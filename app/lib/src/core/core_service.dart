import 'dart:async';

import '../api/controller_client.dart';
import 'core_backend.dart';
import 'core_channel.dart';
import 'core_models.dart';

/// Facade over [CoreBackend] and [ControllerClient].
///
/// The backend owns the lifecycle; the controller client is created lazily once
/// the core reports `running` and torn down on stop, because its address and
/// secret change on every launch.
class CoreService {
  CoreService({CoreBackend? channel}) : _channel = channel ?? CoreChannel() {
    _stateSub = _channel.states.listen(_onState);
  }

  final CoreBackend _channel;
  late final StreamSubscription<CoreState> _stateSub;

  final _stateController = StreamController<CoreState>.broadcast();
  final _clientController = StreamController<ControllerClient?>.broadcast();

  CoreState _state = CoreState.stopped;
  ControllerClient? _client;

  CoreBackend get channel => _channel;

  CoreState get state => _state;

  Stream<CoreState> get states => _stateController.stream;

  /// Emits the live client on start and `null` on stop.
  ///
  /// The current value is replayed to every listener: the underlying broadcast
  /// controller only fires on transitions, so a page that mounts after the core
  /// started would otherwise never see the client.
  Stream<ControllerClient?> get clients async* {
    yield _client;
    yield* _clientController.stream;
  }

  ControllerClient? get client => _client;

  Stream<LogEntry> get logs => _channel.logs;

  Future<String> version() => _channel.version();

  /// Reads the current state from the platform so cold starts (for example after
  /// the tunnel was started from the quick settings tile) are reflected.
  Future<void> refresh() async => _onState(await _channel.state());

  Future<List<InstalledApp>> installedApps() => _channel.installedApps();

  Future<void> validateConfig(String configPath) =>
      _channel.validateConfig(configPath);

  /// Returns false when the user declines the system VPN consent dialog.
  Future<bool> start(StartRequest request) async {
    if (!await _channel.prepareVpn()) return false;
    await _channel.start(request);
    return true;
  }

  /// Applies a new config to an already running tunnel. The platform service
  /// reloads the core in place, so the TUN interface is never re-established
  /// and only [StartRequest.configPath] takes effect.
  Future<void> reload(StartRequest request) => _channel.start(request);

  Future<void> stop() => _channel.stop();

  Future<Traffic> traffic() => _channel.traffic();

  Future<Traffic> trafficTotal() => _channel.trafficTotal();

  Future<void> _onState(CoreState next) async {
    if (next == _state && (next != CoreState.running || _client != null)) {
      return;
    }
    _state = next;

    if (next == CoreState.running) {
      final info = await _channel.controllerInfo();
      if (info.isReady) _swapClient(ControllerClient(info));
    } else if (next == CoreState.stopped) {
      _swapClient(null);
    }

    _stateController.add(next);
  }

  void _swapClient(ControllerClient? next) {
    _client?.close();
    _client = next;
    _clientController.add(next);
  }

  Future<void> dispose() async {
    await _stateSub.cancel();
    _swapClient(null);
    await _stateController.close();
    await _clientController.close();
    await _channel.dispose();
  }
}
