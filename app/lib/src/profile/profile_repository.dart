import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/core_channel.dart';
import 'profile_models.dart';
import 'profile_store.dart';
import 'subscription_fetcher.dart';

/// Owns the profile lifecycle: fetch, convert, override, materialize, validate.
///
/// Layering is `subscription body -> user override -> runtime.yaml`. The
/// subscription body is kept verbatim so re-applying an override never requires
/// a new download, and `runtime.yaml` is always validated by the core before it
/// is handed to the tunnel.
class ProfileRepository {
  ProfileRepository({
    required this.channel,
    ProfileStore? store,
    SubscriptionFetcher? fetcher,
  }) : _store = store ?? ProfileStore(),
       _fetcher = fetcher ?? SubscriptionFetcher();

  final CoreChannel channel;
  final ProfileStore _store;
  final SubscriptionFetcher _fetcher;

  Directory? _root;

  Future<List<Profile>> load() => _store.load();

  Future<String?> activeProfileId() => _store.activeProfileId();

  Future<void> setActiveProfileId(String? id) => _store.setActiveProfileId(id);

  Future<void> save(List<Profile> profiles) => _store.save(profiles);

  String newProfileId() =>
      'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// Downloads a subscription, normalizes it and stores the body on disk.
  /// Returns the profile updated with quota info and, if it had a placeholder
  /// name, the name suggested by the server.
  Future<Profile> updateRemote(Profile profile) async {
    final url = profile.url;
    if (!profile.isRemote || url == null || url.isEmpty) {
      throw SubscriptionException('Profile has no subscription URL');
    }

    final payload = await _fetcher.fetch(url);
    final normalized = await channel.convertSubscription(payload.body);
    await _writeBody(profile.id, normalized);

    final suggested = payload.suggestedName;
    return profile.copyWith(
      name: profile.name.isEmpty && suggested != null ? suggested : null,
      updatedAt: DateTime.now(),
      userInfo: payload.userInfo,
    );
  }

  /// Imports a config the user supplied directly, normalizing it the same way.
  Future<Profile> importLocal(Profile profile, String rawBody) async {
    final normalized = await channel.convertSubscription(rawBody);
    await _writeBody(profile.id, normalized);
    return profile.copyWith(updatedAt: DateTime.now());
  }

  /// Merges the override onto the stored body, writes `runtime.yaml` and asks
  /// the core to parse it. Returns the path to pass to `start`.
  Future<String> materialize(Profile profile, {String? globalPatchYaml}) async {
    final bodyFile = await _bodyFile(profile.id);
    if (!await bodyFile.exists()) {
      throw SubscriptionException('Profile has not been downloaded yet');
    }

    var merged = await bodyFile.readAsString();
    for (final patch in [profile.overrideYaml, globalPatchYaml ?? '']) {
      if (patch.trim().isEmpty) continue;
      merged = await channel.mergeConfig(merged, patch);
    }

    final runtime = await _runtimeFile(profile.id);
    await runtime.writeAsString(merged, flush: true);

    // Surfaces a parse error before the tunnel is brought up.
    await channel.validateConfig(runtime.path);
    return runtime.path;
  }

  Future<String?> readBody(String profileId) async {
    final file = await _bodyFile(profileId);
    return await file.exists() ? file.readAsString() : null;
  }

  /// Replaces the stored body with user-edited YAML once the core accepts it.
  /// A later remote update overwrites these edits.
  Future<void> writeBody(String profileId, String content) async {
    final draft = await _profileFile(profileId, 'draft.yaml');
    await draft.writeAsString(content, flush: true);
    try {
      await channel.validateConfig(draft.path);
    } finally {
      if (await draft.exists()) await draft.delete();
    }
    await _writeBody(profileId, content);
  }

  Future<void> delete(String profileId) async {
    final dir = Directory('${(await _profilesRoot()).path}/$profileId');
    if (await dir.exists()) await dir.delete(recursive: true);
    await _store.deleteSecrets(profileId);
  }

  void close() => _fetcher.close();

  Future<void> _writeBody(String profileId, String content) async {
    final file = await _bodyFile(profileId);
    await file.writeAsString(content, flush: true);
  }

  Future<File> _bodyFile(String id) async => _profileFile(id, 'source.yaml');

  Future<File> _runtimeFile(String id) async =>
      _profileFile(id, 'runtime.yaml');

  Future<File> _profileFile(String id, String name) async {
    final dir = Directory('${(await _profilesRoot()).path}/$id');
    await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }

  Future<Directory> _profilesRoot() async {
    final cached = _root;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/profiles');
    await root.create(recursive: true);
    return _root = root;
  }
}
