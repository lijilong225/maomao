import 'package:flutter/widgets.dart';

import '../core/core_models.dart';

/// Locales the UI ships translations for.
const supportedLocales = [Locale('en'), Locale('zh')];

/// User-wide settings, independent of any single profile.
///
/// [overrideYaml] is merged after the profile's own override, so it always wins.
class AppSettings {
  const AppSettings({
    this.tunStack = TunStack.gvisor,
    this.ipv6 = false,
    this.bypassPrivateRoutes = true,
    this.allowedApps = const [],
    this.disallowedApps = const [],
    this.overrideYaml = '',
    this.autoUpdateOnLaunch = true,
    this.logLevel = LogLevel.info,
    this.locale,
  });

  final TunStack tunStack;
  final bool ipv6;
  final bool bypassPrivateRoutes;

  /// When non-empty, only these packages are tunnelled.
  final List<String> allowedApps;

  /// Packages excluded from the tunnel; ignored when [allowedApps] is set.
  final List<String> disallowedApps;

  final String overrideYaml;
  final bool autoUpdateOnLaunch;
  final LogLevel logLevel;

  /// Null follows the system locale.
  final Locale? locale;

  AppSettings copyWith({
    TunStack? tunStack,
    bool? ipv6,
    bool? bypassPrivateRoutes,
    List<String>? allowedApps,
    List<String>? disallowedApps,
    String? overrideYaml,
    bool? autoUpdateOnLaunch,
    LogLevel? logLevel,
    Locale? locale,
    bool clearLocale = false,
  }) => AppSettings(
    tunStack: tunStack ?? this.tunStack,
    ipv6: ipv6 ?? this.ipv6,
    bypassPrivateRoutes: bypassPrivateRoutes ?? this.bypassPrivateRoutes,
    allowedApps: allowedApps ?? this.allowedApps,
    disallowedApps: disallowedApps ?? this.disallowedApps,
    overrideYaml: overrideYaml ?? this.overrideYaml,
    autoUpdateOnLaunch: autoUpdateOnLaunch ?? this.autoUpdateOnLaunch,
    logLevel: logLevel ?? this.logLevel,
    locale: clearLocale ? null : locale ?? this.locale,
  );

  Map<String, dynamic> toJson() => {
    'tunStack': tunStack.wireName,
    'ipv6': ipv6,
    'bypassPrivateRoutes': bypassPrivateRoutes,
    'allowedApps': allowedApps,
    'disallowedApps': disallowedApps,
    'overrideYaml': overrideYaml,
    'autoUpdateOnLaunch': autoUpdateOnLaunch,
    'logLevel': logLevel.name,
    'locale': locale?.languageCode ?? '',
  };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
    tunStack: TunStack.values.firstWhere(
      (stack) => stack.wireName == json['tunStack'],
      orElse: () => TunStack.gvisor,
    ),
    ipv6: json['ipv6'] as bool? ?? false,
    bypassPrivateRoutes: json['bypassPrivateRoutes'] as bool? ?? true,
    allowedApps: (json['allowedApps'] as List<dynamic>? ?? const [])
        .cast<String>(),
    disallowedApps: (json['disallowedApps'] as List<dynamic>? ?? const [])
        .cast<String>(),
    overrideYaml: json['overrideYaml'] as String? ?? '',
    autoUpdateOnLaunch: json['autoUpdateOnLaunch'] as bool? ?? true,
    logLevel: LogLevel.parse(json['logLevel'] as String? ?? 'info'),
    locale: _parseLocale(json['locale'] as String? ?? ''),
  );

  static Locale? _parseLocale(String tag) => supportedLocales
      .where((locale) => locale.languageCode == tag)
      .firstOrNull;
}
