import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/controller_client.dart';
import '../api/controller_models.dart';
import 'core_models.dart';
import 'core_service.dart';
import 'geo_assets.dart';

final coreServiceProvider = Provider<CoreService>((ref) {
  final service = CoreService();
  ref.onDispose(service.dispose);
  return service;
});

final coreStateProvider = StreamProvider<CoreState>((ref) {
  final service = ref.watch(coreServiceProvider);
  // Sync the initial value; the platform replays state on listen too.
  service.refresh();
  return service.states;
});

final controllerClientProvider = StreamProvider<ControllerClient?>((ref) {
  final service = ref.watch(coreServiceProvider);
  // A page can be the first thing to ask for the client, for example after a
  // hot restart while the tunnel is already up, so pull the platform state.
  service.refresh();
  return service.clients;
});

final coreVersionProvider = FutureProvider<String>(
  (ref) => ref.watch(coreServiceProvider).version(),
);

final installedAppsProvider = FutureProvider<List<InstalledApp>>(
  (ref) => ref.watch(coreServiceProvider).installedApps(),
);

/// Live traffic rate, sourced from the controller websocket while running.
final trafficProvider = StreamProvider<Traffic>((ref) {
  final client = ref.watch(controllerClientProvider).valueOrNull;
  if (client == null) return Stream.value(const Traffic.zero());
  return client.trafficStream();
});

final proxiesProvider = FutureProvider<ProxySnapshot>((ref) async {
  final client = ref.watch(controllerClientProvider).valueOrNull;
  if (client == null) return ProxySnapshot.empty;
  return client.snapshot();
});

final proxyProvidersProvider = FutureProvider<List<ProxyProviderInfo>>((
  ref,
) async {
  final client = ref.watch(controllerClientProvider).valueOrNull;
  if (client == null) return const [];
  return client.proxyProviders();
});

final ruleProvidersProvider = FutureProvider<List<RuleProviderInfo>>((
  ref,
) async {
  final client = ref.watch(controllerClientProvider).valueOrNull;
  if (client == null) return const [];
  return client.ruleProviders();
});

final geoAssetRepositoryProvider = Provider<GeoAssetRepository>(
  (ref) => const GeoAssetRepository(),
);

final geoAssetsProvider = FutureProvider<List<GeoAsset>>(
  (ref) => ref.watch(geoAssetRepositoryProvider).list(),
);

final connectionsProvider = StreamProvider<ConnectionSnapshot>((ref) {
  final client = ref.watch(controllerClientProvider).valueOrNull;
  if (client == null) return Stream.value(const ConnectionSnapshot.empty());
  return client.connectionStream();
});

/// Rolling log buffer, capped so long sessions do not grow without bound.
final logBufferProvider = StreamProvider<List<LogEntry>>((ref) {
  const limit = 500;
  final buffer = <LogEntry>[];
  return ref.watch(coreServiceProvider).logs.map((entry) {
    buffer.insert(0, entry);
    if (buffer.length > limit) buffer.removeRange(limit, buffer.length);
    return List<LogEntry>.unmodifiable(buffer);
  });
});
