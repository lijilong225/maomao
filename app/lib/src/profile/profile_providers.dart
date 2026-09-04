import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/controller_client.dart';
import '../api/controller_models.dart';
import '../core/core_backend.dart';
import '../core/core_models.dart';
import '../core/core_providers.dart';
import '../core/core_service.dart';
import 'config_outline.dart';
import 'latency_probe.dart';
import 'profile_models.dart';
import 'profile_repository.dart';
import 'provider_cache.dart';
import 'provider_updater.dart';
import 'selection_store.dart';
import 'subscription_fetcher.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final repository = ProfileRepository(
    channel: ref.watch(coreServiceProvider).channel,
  );
  ref.onDispose(repository.close);
  return repository;
});

class ProfileState {
  const ProfileState({this.profiles = const [], this.activeId, this.busyId});

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

/// Downloads a provider body straight into the core's cache.
///
/// Only used while the core is down; otherwise the controller refreshes it.
final offlineProviderUpdaterProvider = Provider<OfflineProviderUpdater>((ref) {
  final fetcher = SubscriptionFetcher();
  ref.onDispose(fetcher.close);
  return OfflineProviderUpdater(
    fetcher: fetcher,
    cache: ref.watch(providerCacheProvider),
  );
});

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

/// Delay measured by the app itself, keyed by node name; 0 means the node never
/// answered.
///
/// Kept out of [activeProfileOutlineProvider] because that snapshot is rebuilt
/// on every refresh and carries no latency history.
class OfflineLatencyController extends StateNotifier<Map<String, int>> {
  OfflineLatencyController({
    required this.probe,
    required this.core,
    required this.loadSource,
  }) : super(const {});

  final LatencyProbe probe;
  final CoreService core;

  /// Reads the profile the core has to rebuild, or null when none is active.
  final Future<DelayProbeSource?> Function() loadSource;

  /// Servers dialled at once, so a provider with hundreds of nodes does not
  /// open hundreds of sockets.
  static const _parallelism = 8;

  Future<void> measureAll(Iterable<ProxyNode> nodes) async {
    final targets = [
      for (final node in nodes)
        if (node.hasEndpoint) node,
    ];
    if (targets.isEmpty) return;

    final measured = await _probeViaCore(targets);
    if (!mounted) return;
    if (measured.isNotEmpty) state = {...state, ...measured};

    // A node the core could not rebuild, for example because its protocol needs
    // a build tag this release omits, still gets the handshake lower bound.
    await _handshake([
      for (final node in targets)
        if (!measured.containsKey(node.name)) node,
    ]);
  }

  Future<Map<String, int>> _probeViaCore(List<ProxyNode> targets) async {
    final source = await loadSource();
    if (source == null) return const {};
    try {
      return await core.probeDelay(
        DelayProbeRequest(
          configYaml: source.configYaml,
          providerBodies: source.providerBodies,
          names: [for (final node in targets) node.name],
          concurrency: _parallelism,
        ),
      );
    } on CoreException {
      return const {};
    }
  }

  Future<void> _handshake(List<ProxyNode> targets) async {
    var next = 0;

    Future<void> worker() async {
      while (next < targets.length) {
        final node = targets[next++];
        final delay = await probe.measure(node.server!, node.port!);
        if (!mounted) return;
        state = {...state, node.name: delay};
      }
    }

    await Future.wait([
      for (var i = 0; i < _parallelism && i < targets.length; i++) worker(),
    ]);
  }
}

/// What the core needs to rebuild the active profile's nodes for a probe.
typedef DelayProbeSource =
    ({String configYaml, Map<String, String> providerBodies});

final offlineLatencyProvider =
    StateNotifierProvider<OfflineLatencyController, Map<String, int>>((ref) {
      return OfflineLatencyController(
        probe: const LatencyProbe(),
        core: ref.watch(coreServiceProvider),
        loadSource: () async {
          final id = ref.read(profileControllerProvider).activeId;
          if (id == null) return null;
          final body = await ref.read(profileRepositoryProvider).readBody(id);
          if (body == null) return null;
          final bodies = await ref
              .read(providerCacheProvider)
              .read(parseConfigProviders(body));
          return (configYaml: body, providerBodies: bodies);
        },
      );
    });

/// Member picked for each policy group, by group name.
///
/// While the core runs it owns the selection; this mirror exists so a choice
/// made with the tunnel down is not lost and can be replayed on the next start.
class ProxySelectionController extends StateNotifier<Map<String, String>> {
  ProxySelectionController(this._store, this._profileId) : super(const {}) {
    _restore();
  }

  final ProxySelectionStore _store;
  final String? _profileId;

  Future<void> _restore() async {
    final stored = await _store.load(_profileId);
    if (!mounted || stored.isEmpty) return;
    // A choice made before the disk read finished wins.
    state = {...stored, ...state};
  }

  Future<void> select(String group, String member) async {
    state = {...state, group: member};
    await _store.save(_profileId, state);
  }

  /// Hands every remembered choice to the core; groups it no longer knows are
  /// rejected one by one and skipped.
  Future<void> pushTo(ControllerClient client) async {
    for (final entry in state.entries) {
      try {
        await client.selectProxy(entry.key, entry.value);
      } catch (_) {
        continue;
      }
    }
  }
}

final proxySelectionProvider =
    StateNotifierProvider<ProxySelectionController, Map<String, String>>((ref) {
      final controller = ProxySelectionController(
        const ProxySelectionStore(),
        ref.watch(profileControllerProvider.select((state) => state.activeId)),
      );
      ref.listen(controllerClientProvider, (_, next) async {
        final client = next.valueOrNull;
        if (client == null) return;
        await controller.pushTo(client);
        ref.invalidate(proxiesProvider);
      });
      return controller;
    });

/// One provider collection of the active profile, read from its config file and
/// the bodies the core cached on disk.
class ProfileProviderEntry {
  const ProfileProviderEntry({required this.ref, this.count, this.updatedAt});

  final ConfigProviderRef ref;

  /// Nodes or rules currently available offline, or null when the format is a
  /// binary bundle that cannot be counted without decoding it.
  final int? count;

  /// Timestamp of the cached body; null when it was never downloaded.
  final DateTime? updatedAt;
}

/// Provider collections of the active profile as declared in its config file.
///
/// Mirrors what `/providers/{proxies,rules}` reports so both collections stay
/// browsable while the core is down. Counts and timestamps come from the cache
/// files the core left behind, so a never-updated provider lists nothing.
final activeProfileProvidersProvider =
    FutureProvider.family<List<ProfileProviderEntry>, ProviderSection>((
      ref,
      section,
    ) async {
      final id = ref.watch(profileControllerProvider).activeId;
      if (id == null) return const [];
      final body = await ref.watch(profileRepositoryProvider).readBody(id);
      if (body == null) return const [];

      final refs = parseConfigProviderRefs(body, section);
      final cached = await ref
          .watch(providerCacheProvider)
          .readWithStat(refs.where((entry) => entry.isFetched));

      return [
        for (final entry in refs)
          if (!entry.isFetched)
            // An inline payload lives in the config file itself.
            ProfileProviderEntry(ref: entry, count: entry.payloadCount)
          else
            ProfileProviderEntry(
              ref: entry,
              count: switch (cached[entry.name]) {
                null => 0,
                final hit when section == ProviderSection.proxies =>
                  countProviderProxies(hit.body),
                final hit => countProviderRules(hit.body, entry.format),
              },
              updatedAt: cached[entry.name]?.updatedAt,
            ),
      ];
    });
