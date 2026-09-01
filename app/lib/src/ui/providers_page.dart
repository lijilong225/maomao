import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../api/controller_models.dart';
import '../core/core_providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(controllerClientProvider).valueOrNull != null;
    final entries = _isProxy
        ? ref.watch(proxyProvidersProvider).valueOrNull
        : ref.watch(ruleProvidersProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isProxy ? l10n.menuProxyProviders : l10n.menuRuleProviders),
        actions: [
          if (live && entries != null && entries.isNotEmpty)
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
                    onPressed: _updateAll,
                  ),
        ],
      ),
      body: !live
          ? _Centered(text: l10n.providersRequireCore)
          : entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? _Centered(text: l10n.providersEmpty)
          : RefreshIndicator(
              onRefresh: () async => _invalidate(),
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) => _tile(l10n, entries[index]),
              ),
            ),
    );
  }

  Widget _tile(AppLocalizations l10n, Object entry) {
    final String name;
    final String subtitle;
    final bool updatable;
    final DateTime? updatedAt;

    if (entry is ProxyProviderInfo) {
      name = entry.name;
      subtitle = l10n.providerNodeCount(entry.proxyCount);
      updatable = entry.isUpdatable;
      updatedAt = entry.updatedAt;
    } else {
      final rule = entry as RuleProviderInfo;
      name = rule.name;
      subtitle = [
        l10n.providerRuleCount(rule.ruleCount),
        rule.behavior,
        if (rule.format.isNotEmpty) rule.format,
      ].where((part) => part.isNotEmpty).join(' · ');
      updatable = rule.isUpdatable;
      updatedAt = rule.updatedAt;
    }

    return ListTile(
      title: Text(name),
      subtitle: Text(
        '$subtitle\n${updatable ? l10n.profileUpdated(formatRelative(l10n, updatedAt)) : l10n.providerNotUpdatable}',
      ),
      isThreeLine: true,
      trailing: !updatable
          ? null
          : _busy.contains(name)
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.actionUpdate,
              onPressed: () => _updateOne(name),
            ),
    );
  }

  Future<void> _updateOne(String name) async {
    setState(() => _busy.add(name));
    try {
      await _update(name);
      _invalidate();
    } catch (error) {
      if (mounted) {
        _notify(
          AppLocalizations.of(context).providerUpdateFailed(name, '$error'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(name));
    }
  }

  Future<void> _updateAll() async {
    final entries = _isProxy
        ? ref.read(proxyProvidersProvider).valueOrNull
        : ref.read(ruleProvidersProvider).valueOrNull;
    final names = [
      for (final entry in entries ?? const <Object>[])
        if (entry is ProxyProviderInfo && entry.isUpdatable)
          entry.name
        else if (entry is RuleProviderInfo && entry.isUpdatable)
          entry.name,
    ];
    if (names.isEmpty) return;

    setState(() => _updatingAll = true);
    var done = 0;
    var failed = 0;
    // Sequential on purpose: a subscription host throttles parallel fetches.
    for (final name in names) {
      try {
        await _update(name);
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

  Future<void> _update(String name) async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null) return;
    return _isProxy
        ? client.updateProxyProvider(name)
        : client.updateRuleProvider(name);
  }

  void _invalidate() {
    ref.invalidate(_isProxy ? proxyProvidersProvider : ruleProvidersProvider);
    if (_isProxy) ref.invalidate(proxiesProvider);
  }

  void _notify(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Text(text)),
  );
}
