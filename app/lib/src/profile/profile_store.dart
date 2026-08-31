import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_models.dart';

/// Persists profile metadata.
///
/// Subscription URLs often embed a token, so they are kept in encrypted storage
/// (Android Keystore) while the rest of the metadata lives in plain preferences.
class ProfileStore {
  ProfileStore({FlutterSecureStorage? secureStorage})
    : _secure =
          secureStorage ??
          const FlutterSecureStorage(
            // Keystore-backed EncryptedSharedPreferences (API 23+).
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _profilesKey = 'profiles';
  static const _activeKey = 'active_profile';
  static const _urlPrefix = 'profile_url_';

  final FlutterSecureStorage _secure;

  Future<List<Profile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_profilesKey) ?? const [];

    final profiles = <Profile>[];
    for (final entry in raw) {
      final decoded = jsonDecode(entry);
      if (decoded is! Map<String, dynamic>) continue;
      final profile = Profile.fromJson(decoded);
      final url = profile.isRemote
          ? await _secure.read(key: '$_urlPrefix${profile.id}')
          : null;
      profiles.add(url != null ? profile.copyWith(url: url) : profile);
    }
    return profiles;
  }

  Future<void> save(List<Profile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _profilesKey,
      profiles
          .map((p) => jsonEncode(p.toJson(includeUrl: false)))
          .toList(growable: false),
    );

    for (final profile in profiles) {
      final url = profile.url;
      if (profile.isRemote && url != null && url.isNotEmpty) {
        await _secure.write(key: '$_urlPrefix${profile.id}', value: url);
      }
    }
  }

  Future<void> deleteSecrets(String profileId) =>
      _secure.delete(key: '$_urlPrefix$profileId');

  Future<String?> activeProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  Future<void> setActiveProfileId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, id);
    }
  }
}
