import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/controller_models.dart';
import '../core/core_providers.dart';
import 'config_outline.dart';
import 'profile_models.dart';
import 'profile_repository.dart';
import 'provider_cache.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final repository = ProfileRepository(
    channel: ref.watch(coreServiceProvider).channel,
  );
  ref.onDispose(repository.close);
  return repository;
});

class ProfileState {
  const ProfileState({
    this.profiles = const [],
    this.activeId,
    this.busyId,
  });

  final List<Profile> profiles;
  final String? activeId;

  /// Id of the profile currently being downloaded, if any.
  final String? busyId;

  Profile? get active {
    final id = activeId;
    if (id == null) return null;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  ProfileState copyWith({
    List<Profile>? profiles,
    String? activeId,
    bool clearActive = false,
    String? busyId,
    bool clearBusy = false,
  }) => ProfileState(
    profiles: profiles ?? this.profiles,
    activeId: clearActive ? null : (activeId ?? this.activeId),
    busyId: clearBusy ? null : (busyId ?? this.busyId),
  );
}

class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this._repository) : super(const ProfileState()) {
    _restore();
  }

  final ProfileRepository _repository;

  Future<void> _restore() async {
    final profiles = await _repository.load();
    var activeId = await _repository.activeProfileId();
    if (activeId != null && !profiles.any((p) => p.id == activeId)) {
      activeId = null;
    }
    if (!mounted) return;
    state = ProfileState(profiles: profiles, activeId: activeId);
  }

  Future<Profile> addRemote({
    required String url,
    String name = '',
    Duration? autoUpdateInterval,
  }) async {
    final profile = Profile(
      id: _repository.newProfileId(),
      name: name.isEmpty ? Uri.tryParse(url)?.host ?? 'subscription' : name,
      source: ProfileSource.remote,
      url: url,
      autoUpdateInterval: autoUpdateInterval,
    );
    await _upsert(profile);
    return update(profile.id);
  }

  Future<Profile> addLocal({required String name, required String body}) async {
    final draft = Profile(
      id: _repository.newProfileId(),
      name: name.isEmpty ? 'local' : name,
      source: ProfileSource.local,
    );
    final imported = await _repository.importLocal(draft, body);
    await _upsert(imported);
    if (state.activeId == null) await setActive(imported.id);
    return imported;
  }

  Future<Profile> update(String id) async {
    final profile = _find(id);
    if (profile == null) throw StateError('Unknown profile $id');

    state = state.copyWith(busyId: id);
    try {
      final updated = await _repository.updateRemote(profile);
      await _upsert(updated);
      if (state.activeId == null) await setActive(updated.id);
      return updated;
    } finally {
      if (mounted) state = state.copyWith(clearBusy: true);
    }
  }

  /// Refreshes every remote profile whose auto-update interval has elapsed.
  Future<void> updateStale() async {
    for (final profile in state.profiles.where((p) => p.needsUpdate)) {
      try {
        await update(profile.id);
      } catch (_) {
        // A single unreachable subscription must not abort the rest.
      }
    }
  }

  Future<void> setOverride(String id, String overrideYaml) async {
    final profile = _find(id);
    if (profile == null) return;
    await _upsert(profile.copyWith(overrideYaml: overrideYaml));
  }

  Future<String?> readBody(String id) => _repository.readBody(id);

  /// Persists a hand-edited config. Remote updates overwrite it.
  Future<void> writeBody(String id, String content) =>
      _repository.writeBody(id, content);

  Future<void> rename(String id, String name) async {
    final profile = _find(id);
    if (profile == null || name.isEmpty) return;
    await _upsert(profile.copyWith(name: name));
  }

  Future<void> setAutoUpdate(String id, Duration? interval) async {
    final profile = _find(id);
    if (profile == null) return;
    await _upsert(
      profile.copyWith(
        autoUpdateInterval: interval,
        clearAutoUpdate: interval == null,
      ),
    );
  }

  Future<void> setActive(String id) async {
    await _repository.setActiveProfileId(id);
    if (!mounted) return;
    state = state.copyWith(activeId: id);
  }

  Future<void> remove(String id) async {
    await _repository.delete(id);
    final remaining = state.profiles.where((p) => p.id != id).toList();
    await _repository.save(remaining);

    final wasActive = state.activeId == id;
    if (wasActive) await _repository.setActiveProfileId(null);
    if (!mounted) return;
    state = ProfileState(
      profiles: remaining,
      activeId: wasActive ? null : state.activeId,
    );
  }

  /// Produces the validated `runtime.yaml` path for the active profile.
  Future<String> materializeActive({String? globalPatchYaml}) async {
    final profile = state.active;
    if (profile == null) throw StateError('No active profile');
    return _repository.materialize(profile, globalPatchYaml: globalPatchYaml);
  }

  Profile? _find(String id) {
    for (final profile in state.profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> _upsert(Profile profile) async {
    final profiles = [...state.profiles];
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _repository.save(profiles);
    if (!mounted) return;
    state = state.copyWith(profiles: profiles);
  }
}

final profileControllerProvider =
    StateNotifierProvider<ProfileController, ProfileState>(
      (ref) => ProfileController(ref.watch(profileRepositoryProvider)),
    );

final providerCacheProvider = Provider<ProviderCache>(
  (ref) => const ProviderCache(),
);

/// Policy groups of the active profile as declared in its config file.
///
/// Only used while the core is down; once it runs the controller is the source
/// of truth because it also resolves providers and holds latency history.
final activeProfileOutlineProvider = FutureProvider<ProxySnapshot>((ref) async {
  final id = ref.watch(profileControllerProvider).activeId;
  if (id == null) return ProxySnapshot.empty;
  final body = await ref.watch(profileRepositoryProvider).readBody(id);
  if (body == null) return ProxySnapshot.empty;
  // Groups built from `use:` or `include-all` only have members once the
  // provider bodies the core already downloaded are read back.
  final bodies = await ref
      .watch(providerCacheProvider)
      .read(parseConfigProviders(body));
  return parseConfigOutline(body, providerBodies: bodies);
});
