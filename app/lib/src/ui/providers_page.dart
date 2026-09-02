import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../api/controller_models.dart';
import '../core/core_providers.dart';
import '../profile/config_outline.dart';
import '../profile/profile_providers.dart';
import 'format.dart';

enum ProviderKind { proxy, rule }

/// Opens the provider collections of the active profile.
class ProvidersMenuButton extends StatelessWidget {
  const ProvidersMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<ProviderKind>(
      icon: const Icon(Icons.folder_copy_outlined),
      onSelected: (kind) => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => ProvidersPage(kind: kind)),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: ProviderKind.rule,
          child: Text(l10n.menuRuleProviders),
        ),
        PopupMenuItem(
          value: ProviderKind.proxy,
          child: Text(l10n.menuProxyProviders),
        ),
      ],
    );
  }
}

class ProvidersPage extends ConsumerStatefulWidget {
  const ProvidersPage({super.key, required this.kind});

  final ProviderKind kind;

  @override
  ConsumerState<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends ConsumerState<ProvidersPage> {
  /// Names currently being re-downloaded, so each row can spin on its own.
  final _busy = <String>{};
  bool _updatingAll = false;

  bool get _isProxy => widget.kind == ProviderKind.proxy;

  ProviderSection get _section =>
      _isProxy ? ProviderSection.proxies : ProviderSection.rules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(controllerClientProvider).valueOrNull != null;
    final rows = _rows(l10n, live);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isProxy ? l10n.menuProxyProviders : l10n.menuRuleProviders,
        ),
        actions: [
          if (rows != null && rows.any((row) => row.updatable))
            _updatingAll
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: l10n.providersUpdateAll,
                    onPressed: () => _updateAll(rows),
                  ),
        ],
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? _Centered(text: l10n.providersEmpty)
          : RefreshIndicator(
              onRefresh: () async => _invalidate(),
              child: ListView.builder(
                // A leading note explains where the offline numbers come from.
                itemCount: rows.length + (live ? 0 : 1),
                itemBuilder: (context, index) {
                  if (!live && index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                      child: Text(
                        l10n.providersPreviewOnly,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  return _tile(l10n, rows[live ? index : index - 1]);
                },
              ),
            ),
    );
  }

  /// Null while the source is still loading.
  List<_Row>? _rows(AppLocalizations l10n, bool live) {
    if (live) {
      final entries = _isProxy
          ? ref.watch(proxyProvidersProvider).valueOrNull
          : ref.watch(ruleProvidersProvider).valueOrNull;
      return entries == null
          ? null
          : [for (final entry in entries) _liveRow(l10n, entry)];
    }
    final entries = ref
        .watch(activeProfileProvidersProvider(_section))
        .valueOrNull;
    return entries == null
        ? null
        : [for (final entry in entries) _offlineRow(l10n, entry)];
  }

  _Row _liveRow(AppLocalizations l10n, Object entry) {
    if (entry is ProxyProviderInfo) {
      return _Row(
        name: entry.name,
        detail: l10n.providerNodeCount(entry.proxyCount),
        status: entry.isUpdatable
            ? l10n.profileUpdated(formatRelative(l10n, entry.updatedAt))
            : l10n.providerNotUpdatable,
        updatable: entry.isUpdatable,
      );
    }
    final rule = entry as RuleProviderInfo;
    return _Row(
      name: rule.name,
      detail: _join([
        l10n.providerRuleCount(rule.ruleCount),
        rule.behavior,
        rule.format,
      ]),
      status: rule.isUpdatable
          ? l10n.profileUpdated(formatRelative(l10n, rule.updatedAt))
          : l10n.providerNotUpdatable,
      updatable: rule.isUpdatable,
    );
  }

  /// Offline rows update through the app itself, which can only refresh what it
  /// is able to download.
  _Row _offlineRow(AppLocalizations l10n, ProfileProviderEntry entry) {
    final count = entry.count;
    final updatedAt = entry.updatedAt;
    // An inline payload is always available; a fetched one only after a sync.
    final available = !entry.ref.isFetched || updatedAt != null;
    return _Row(
      name: entry.ref.name,
      detail: _isProxy
          ? (available ? l10n.providerNodeCount(count ?? 0) : '')
          : _join([
              // A binary bundle has no countable entries before it is decoded.
              if (available && count != null) l10n.providerRuleCount(count),
              entry.ref.behaviorLabel,
              entry.ref.formatLabel,
            ]),
      status: !entry.ref.isFetched
          ? l10n.providerNotUpdatable
          : updatedAt == null
          ? l10n.providerNotDownloaded
          : l10n.profileUpdated(formatRelative(l10n, updatedAt)),
      updatable: entry.ref.isDownloadable,
      offlineRef: entry.ref,
    );
  }

  Widget _tile(AppLocalizations l10n, _Row row) {
    final lines = [row.detail, row.status].where((line) => line.isNotEmpty);
    return ListTile(
      title: Text(row.name),
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
      trailing: !row.updatable
          ? null
          : _busy.contains(row.name)
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.actionUpdate,
              onPressed: () => _updateOne(row),
            ),
    );
  }

  Future<void> _updateOne(_Row row) async {
    setState(() => _busy.add(row.name));
    try {
      await _update(row);
      _invalidate();
    } catch (error) {
      if (mounted) {
        _notify(
          AppLocalizations.of(context).providerUpdateFailed(row.name, '$error'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(row.name));
    }
  }

  Future<void> _updateAll(List<_Row> rows) async {
    final targets = [
      for (final row in rows)
        if (row.updatable) row,
    ];
    if (targets.isEmpty) return;

    setState(() => _updatingAll = true);
    var done = 0;
    var failed = 0;
    // Sequential on purpose: a subscription host throttles parallel fetches.
    for (final row in targets) {
      try {
        await _update(row);
        done++;
      } catch (_) {
        failed++;
      }
    }
    _invalidate();
    if (!mounted) return;
    setState(() => _updatingAll = false);
    final l10n = AppLocalizations.of(context);
    _notify(
      failed == 0
          ? l10n.providersUpdated(done)
          : l10n.providersUpdatePartial(done, failed),
    );
  }

  /// Refreshes one collection, through the core when it runs and by downloading
  /// into its cache when it does not.
  Future<void> _update(_Row row) async {
    final offline = row.offlineRef;
    if (offline != null) {
      return ref.read(offlineProviderUpdaterProvider).update(offline);
    }
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null) return;
    return _isProxy
        ? client.updateProxyProvider(row.name)
        : client.updateRuleProvider(row.name);
  }

  void _invalidate() {
    ref.invalidate(_isProxy ? proxyProvidersProvider : ruleProvidersProvider);
    ref.invalidate(activeProfileProvidersProvider(_section));
    if (_isProxy) ref.invalidate(proxiesProvider);
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

/// A provider row, filled either from the controller or from the config file.
class _Row {
  const _Row({
    required this.name,
    required this.detail,
    required this.status,
    this.updatable = false,
    this.offlineRef,
  });

  final String name;
  final String detail;
  final String status;
  final bool updatable;

  /// Set on a config-sourced row, which the app refreshes by itself.
  final ConfigProviderRef? offlineRef;
}

String _join(Iterable<String> parts) =>
    parts.where((part) => part.isNotEmpty).join(' · ');

class _Centered extends StatelessWidget {
  const _Centered({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Text(text)),
  );
}
