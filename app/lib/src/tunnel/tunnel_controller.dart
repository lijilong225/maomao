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

      final accepted = await _ref
          .read(coreServiceProvider)
          .start(_request(configPath, settings));

      state = TunnelStatus(
        error: accepted ? null : 'VPN permission was declined',
      );
    } catch (error) {
      state = TunnelStatus(error: _describe(error));
    }
  }

  Future<void> disconnect() async {
    if (state.busy) return;
    state = const TunnelStatus(busy: true);
    try {
      await _ref.read(coreServiceProvider).stop();
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

  StartRequest _request(String configPath, AppSettings settings) => StartRequest(
    configPath: configPath,
    profileName:
        _ref.read(profileControllerProvider).active?.name ?? 'maomao',
    tunStack: settings.tunStack,
    allowedApps: settings.allowedApps,
    disallowedApps: settings.disallowedApps,
    ipv6: settings.ipv6,
    bypassPrivateRoutes: settings.bypassPrivateRoutes,
  );

  String _describe(Object error) => switch (error) {
    StateError() => error.message,
    _ => error.toString(),
  };
}

final tunnelControllerProvider =
    StateNotifierProvider<TunnelController, TunnelStatus>(
      TunnelController.new,
    );
