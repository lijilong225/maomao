import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core_models.dart';
import '../core/core_providers.dart';
import '../profile/profile_providers.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';

class TunnelStatus {
  const TunnelStatus({this.busy = false, this.error});

  final bool busy;
  final String? error;
}

const _handoffTimeout = Duration(seconds: 8);

/// Bridges profiles, settings and the core lifecycle.
///
/// Connecting means: materialize `runtime.yaml` from the active profile plus the
/// global override, then hand its path to the platform tunnel.
class TunnelController extends StateNotifier<TunnelStatus> {
  TunnelController(this._ref) : super(const TunnelStatus());

  final Ref _ref;

  Future<void> connect() async {
    if (state.busy) return;
    state = const TunnelStatus(busy: true);
    try {
      final settings = _ref.read(settingsControllerProvider);
      final configPath = await _ref
          .read(profileControllerProvider.notifier)
          .materializeActive(globalPatchYaml: settings.overrideYaml);

      final service = _ref.read(coreServiceProvider);
      // Subscribed before the request so a core that reacts immediately cannot
      // slip through before we start watching.
      final handoff = _awaitState(service.states, (s) => s != CoreState.stopped);

      final accepted = await service.start(_request(configPath, settings));
      if (!accepted) {
        state = const TunnelStatus(error: 'VPN permission was declined');
        return;
      }

      await handoff;
      state = const TunnelStatus();
    } catch (error) {
      state = TunnelStatus(error: _describe(error));
    }
  }

  Future<void> disconnect() async {
    if (state.busy) return;
    state = const TunnelStatus(busy: true);
    try {
      final service = _ref.read(coreServiceProvider);
      final handoff = _awaitState(service.states, (s) => s == CoreState.stopped);
      await service.stop();
      await handoff;
      state = const TunnelStatus();
    } catch (error) {
      state = TunnelStatus(error: _describe(error));
    }
  }

  Future<void> toggle() async {
    final active = _ref.read(coreStateProvider).valueOrNull?.isActive ?? false;
    return active ? disconnect() : connect();
  }

  /// Re-materializes the config and reloads it without dropping the tunnel.
  Future<void> applyConfigChanges() async {
    final coreState = _ref.read(coreStateProvider).valueOrNull;
    if (coreState != CoreState.running) return;
    state = const TunnelStatus(busy: true);
    try {
      final settings = _ref.read(settingsControllerProvider);
      final configPath = await _ref
          .read(profileControllerProvider.notifier)
          .materializeActive(globalPatchYaml: settings.overrideYaml);
      await _ref
          .read(coreServiceProvider)
          .reload(_request(configPath, settings));
      state = const TunnelStatus();
    } catch (error) {
      state = TunnelStatus(error: _describe(error));
    }
  }

  void clearError() {
    if (state.error != null) state = const TunnelStatus();
  }

  /// Bridges the gap between the platform call returning and the core reporting
  /// its new state, so the UI never falls back to "disconnected" mid-transition.
  ///
  /// The timeout covers the paths where the platform gives up before the core is
  /// ever reached, for example when the TUN interface cannot be established.
  Future<void> _awaitState(
    Stream<CoreState> states,
    bool Function(CoreState) matches,
  ) => states
      .firstWhere(matches)
      .timeout(_handoffTimeout)
      .then<void>((_) {}, onError: (_) {});

  StartRequest _request(String configPath, AppSettings settings) =>
      StartRequest(
        configPath: configPath,
        profileName:
            _ref.read(profileControllerProvider).active?.name ?? 'maomao',
        kernel: settings.kernel,
        tunStack: settings.tunStack,
        allowedApps: settings.allowedApps,
        disallowedApps: settings.disallowedApps,
        ipv6: settings.ipv6,
        bypassPrivateRoutes: settings.bypassPrivateRoutes,
        xrayFragment: settings.xrayFragment,
      );

  String _describe(Object error) => switch (error) {
    StateError() => error.message,
    _ => error.toString(),
  };
}

final tunnelControllerProvider =
    StateNotifierProvider<TunnelController, TunnelStatus>(TunnelController.new);
