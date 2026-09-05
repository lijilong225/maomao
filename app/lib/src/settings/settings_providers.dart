import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/core_models.dart';
import 'app_settings.dart';
import 'release_checker.dart';

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController() : super(const AppSettings()) {
    _restore();
  }

  static const _key = 'app_settings';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return;
    if (!mounted) return;
    state = AppSettings.fromJson(decoded);
  }

  Future<void> _persist(AppSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.toJson()));
  }

  Future<void> setKernel(ProxyKernel kernel) =>
      _persist(state.copyWith(kernel: kernel));

  Future<void> setTunStack(TunStack stack) =>
      _persist(state.copyWith(tunStack: stack));

  Future<void> setIpv6(bool enabled) => _persist(state.copyWith(ipv6: enabled));

  Future<void> setBypassPrivateRoutes(bool enabled) =>
      _persist(state.copyWith(bypassPrivateRoutes: enabled));

  Future<void> setAllowedApps(List<String> packages) =>
      _persist(state.copyWith(allowedApps: packages));

  Future<void> setDisallowedApps(List<String> packages) =>
      _persist(state.copyWith(disallowedApps: packages));

  Future<void> setOverrideYaml(String yaml) =>
      _persist(state.copyWith(overrideYaml: yaml));

  Future<void> setAutoUpdateOnLaunch(bool enabled) =>
      _persist(state.copyWith(autoUpdateOnLaunch: enabled));

  Future<void> setLogLevel(LogLevel level) =>
      _persist(state.copyWith(logLevel: level));

  Future<void> setXrayFragment(bool enabled) =>
      _persist(state.copyWith(xrayFragment: enabled));

  /// Null follows the system locale.
  Future<void> setLocale(Locale? locale) =>
      _persist(state.copyWith(locale: locale, clearLocale: locale == null));
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>(
      (ref) => SettingsController(),
    );

final releaseCheckerProvider = Provider<ReleaseChecker>((ref) {
  final checker = ReleaseChecker();
  ref.onDispose(checker.close);
  return checker;
});

/// Installed version, never a failed or empty state.
final appVersionProvider = FutureProvider<String>((ref) => currentAppVersion());
