import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/core_models.dart';

/// Remembers which member the user picked for each policy group.
///
/// The core keeps its own record, but it is unreachable while stopped, so the
/// app has to hold the choice until it can be pushed to the controller.
///
/// Records are scoped per engine because the two cores expose different group
/// names for the same profile.
class ProxySelectionStore {
  const ProxySelectionStore();

  static const _prefix = 'proxy_selection_';

  Future<Map<String, String>> load(String? profileId, CoreEngine engine) async {
    if (profileId == null) return const {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(profileId, engine));
    if (raw == null) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  Future<void> save(
    String? profileId,
    CoreEngine engine,
    Map<String, String> selections,
  ) async {
    if (profileId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(profileId, engine), jsonEncode(selections));
  }

  /// mihomo keeps the original key so existing selections survive the upgrade.
  String _key(String profileId, CoreEngine engine) =>
      engine == CoreEngine.mihomo
      ? '$_prefix$profileId'
      : '$_prefix${engine.wireName}_$profileId';
}
