import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'core_backend.dart';
import 'core_models.dart';

/// Drives the core as a sidecar process, used by desktop hosts where it cannot
/// be linked into the app process.
///
/// The wire format is newline-delimited JSON: requests carry an id and are
/// answered by a `result` frame, while `state` and `log` frames arrive
/// unsolicited. The process is spawned lazily and respawned after it exits.
class CoreProcessBackend extends CoreBackend {
  CoreProcessBackend({this.executablePath, this.homeDirectory});

  static final _executableName = Platform.isWindows
      ? 'maomao-core.exe'
      : 'maomao-core';

  /// Defaults to the sidecar shipped next to the app executable.
  final String? executablePath;

  /// Defaults to the core home directory under the app support directory.
  final String? homeDirectory;
  final _eventController = StreamController<CoreEvent>.broadcast();
  final _pending = <int, Completer<Object?>>{};

  Process? _process;
  Future<Process>? _launch;
  int _nextId = 1;
  bool _disposed = false;

  @override
  Stream<CoreEvent> get events => _eventController.stream;

  @override
  Future<String> version() async => await _invoke<String>('version') ?? '';

  @override
  Future<CoreState> state() async =>
      CoreState.parse(await _invoke<String>('state') ?? '');

  @override
  Future<ControllerInfo> controllerInfo() async => ControllerInfo.fromMap(
    await _invoke<Map<dynamic, dynamic>>('controllerInfo'),
  );

  /// The core owns the TUN interface here, so there is no system consent dialog.
  @override
  Future<bool> prepareVpn() async => true;

  @override
  Future<void> validateConfig(CoreEngine engine, String configPath) => _invoke<
    void
  >('validateConfig', {'engine': engine.wireName, 'configPath': configPath});

  @override
  Future<String> convertSubscription(String raw) async =>
      await _invoke<String>('convertSubscription', {'raw': raw}) ?? '';

  @override
  Future<String> mergeConfig(String base, String patch) async =>
      await _invoke<String>('mergeConfig', {'base': base, 'patch': patch}) ??
      '';

  @override
  Future<String> convertToSingbox(String yaml) async =>
      await _invoke<String>('convertToSingbox', {'yaml': yaml}) ?? '';

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

  /// Per-app proxying is an Android capability.
  @override
  Future<List<InstalledApp>> installedApps() async => const [];

  @override
  Future<void> dispose() async {
    _disposed = true;
    final process = _process;
    _process = null;
    _launch = null;
    if (process != null) {
      // Closing stdin makes the sidecar stop the tunnel and release the TUN
      // interface before it exits.
      await process.stdin.close().catchError((_) {});
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    }
    await _eventController.close();
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final process = await _ensureProcess();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      process.stdin.writeln(
        jsonEncode({'id': id, 'method': method, 'args': ?arguments}),
      );
    } catch (error) {
      _pending.remove(id);
      throw CoreException('unavailable', '$error');
    }
    return await completer.future as T?;
  }

  Future<Process> _ensureProcess() async {
    if (_disposed) {
      throw CoreException('unavailable', 'Core backend is disposed');
    }
    try {
      return await (_launch ??= _spawn());
    } on CoreException {
      _launch = null;
      rethrow;
    } catch (error) {
      _launch = null;
      throw CoreException('spawn_failed', '$error');
    }
  }

  Future<Process> _spawn() async {
    final executable = executablePath ?? await _resolveExecutable();
    final home = homeDirectory ?? await _resolveHome();
    await Directory(home).create(recursive: true);

    final process = await Process.start(executable, ['--home', home]);
    // Config bodies and paths are UTF-8; the default is the system codepage.
    process.stdin.encoding = utf8;
    _process = process;

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onExit, cancelOnError: false);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStderr, cancelOnError: false);

    return process;
  }

  Future<String> _resolveExecutable() async {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final path = '$dir${Platform.pathSeparator}$_executableName';
    if (!await File(path).exists()) {
      throw CoreException('unavailable', 'Core executable is missing: $path');
    }
    return path;
  }

  Future<String> _resolveHome() async {
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}core';
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    Object? raw;
    try {
      raw = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (raw is! Map) return;

    if (raw['type'] != 'result') {
      final event = decodeCoreEvent(raw);
      if (event != null && !_eventController.isClosed) {
        _eventController.add(event);
      }
      return;
    }

    final completer = _pending.remove((raw['id'] as num?)?.toInt() ?? 0);
    if (completer == null) return;
    final failure = raw['error'];
    if (failure is Map) {
      completer.completeError(
        CoreException(
          failure['code'] as String? ?? 'unknown',
          failure['message'] as String?,
        ),
      );
    } else {
      completer.complete(raw['result']);
    }
  }

  void _onStderr(String line) {
    if (line.isEmpty || _eventController.isClosed) return;
    _eventController.add(
      CoreLogEvent(LogEntry(level: LogLevel.error, payload: line)),
    );
  }

  void _onExit() {
    _process = null;
    _launch = null;
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(CoreException('unavailable', 'Core has exited'));
    }
    if (!_eventController.isClosed) {
      _eventController.add(const CoreStateEvent(CoreState.stopped));
    }
  }
}
