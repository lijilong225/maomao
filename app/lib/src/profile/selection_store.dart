import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which member the user picked for each policy group.
///
/// The core keeps its own record, but it is unreachable while stopped, so the
/// app has to hold the choice until it can be pushed to the controller.
class ProxySelectionStore {
  const ProxySelectionStore();

  static const _prefix = 'proxy_selection_';

  Future<Map<String, String>> load(String? profileId) async {
    if (profileId == null) return const {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$profileId');
    if (raw == null) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  Future<void> save(String? profileId, Map<String, String> selections) async {
    if (profileId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$profileId', jsonEncode(selections));
  }
}
