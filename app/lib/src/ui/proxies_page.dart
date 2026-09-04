import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../api/controller_models.dart';
import '../core/core_providers.dart';
import '../profile/profile_providers.dart';
import 'format.dart';

class ProxiesPage extends ConsumerWidget {
  const ProxiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(controllerClientProvider).valueOrNull != null;
    final snapshot = live
        ? ref.watch(proxiesProvider)
        : ref.watch(activeProfileOutlineProvider);
    final l10n = AppLocalizations.of(context);

    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: l10n.proxiesUnavailable('$error')),
      data: (data) {
        final groups = data.groups;
        if (groups.isEmpty) {
          return _Message(text: l10n.proxiesEmpty);
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(
            live ? proxiesProvider : activeProfileOutlineProvider,
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length + (live ? 0 : 1),
            itemBuilder: (context, index) {
              if (!live && index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Text(
                    '${l10n.proxiesPreviewOnly} ${l10n.offlineLatencyHint}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              final group = groups[live ? index : index - 1];
              return _GroupTile(group: group, nodes: data.nodes, live: live);
            },
          ),
        );
      },
    );
  }
}

class _GroupTile extends ConsumerStatefulWidget {
  const _GroupTile({
    required this.group,
    required this.nodes,
    required this.live,
  });

  final ProxyNode group;
  final Map<String, ProxyNode> nodes;

  /// False while the core is down, which is when latency has to be measured by
  /// the app itself and a selection can only be recorded for later.
  final bool live;

  @override
  ConsumerState<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends ConsumerState<_GroupTile> {
  bool _testing = false;

  ProxyNode get group => widget.group;

  bool get _canSelect => group.isSelectable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final measured = widget.live
        ? const <String, int>{}
        : ref.watch(offlineLatencyProvider);
    // While the core runs it owns the selection, so trust what it reports.
    final current = widget.live
        ? group.now
        : ref.watch(proxySelectionProvider)[group.name] ?? group.now;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        title: Text(group.name),
        subtitle: Text('${group.type} · ${current ?? '—'}'),
        trailing: _testing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.speed),
                tooltip: l10n.testLatency,
                onPressed: _testGroup,
              ),
        children: [
          if (group.all.isEmpty)
            ListTile(
              dense: true,
              enabled: false,
              title: Text(l10n.proxiesMembersUnavailable),
            ),
          for (final member in group.all)
            ListTile(
              dense: true,
              enabled: _canSelect,
              leading: Icon(
                member == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
              ),
              title: Text(member),
              trailing: widget.live
                  ? Text(formatDelay(widget.nodes[member]?.latestDelay ?? 0))
                  : _offlineResult(member, measured, l10n),
              onTap: _canSelect ? () => _select(member) : null,
            ),
        ],
      ),
    );
  }

  /// Nothing for a member the app cannot dial itself, such as DIRECT or a
  /// nested group; otherwise the measured delay or a plain failure.
  Widget? _offlineResult(
    String member,
    Map<String, int> measured,
    AppLocalizations l10n,
  ) {
    if (!(widget.nodes[member]?.hasEndpoint ?? false)) return null;
    final delay = measured[member];
    if (delay == null) return Text(formatDelay(0));
    return Text(delay > 0 ? formatDelay(delay) : l10n.nodeUnreachable);
  }

  Future<void> _select(String? member) async {
    if (member == null) return;
    await ref.read(proxySelectionProvider.notifier).select(group.name, member);
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null) return;
    try {
      await client.selectProxy(group.name, member);
      ref.invalidate(proxiesProvider);
    } catch (error) {
      if (mounted) _notify('$error');
    }
  }

  Future<void> _testGroup() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      await (widget.live ? _testViaCore() : _testEndpoints());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _testViaCore() async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null) return;
    try {
      await client.groupDelay(group.name);
      ref.invalidate(proxiesProvider);
    } catch (_) {
      // The controller answers 504 when every member times out.
      if (mounted) _notify(AppLocalizations.of(context).latencyTestFailed);
    }
  }

  /// Rebuilds the members as standalone outbounds and times a request through
  /// each; every row reports its own outcome.
  Future<void> _testEndpoints() =>
      ref.read(offlineLatencyProvider.notifier).measureAll([
        for (final member in group.all)
          if (widget.nodes[member] != null) widget.nodes[member]!,
      ]);

  void _notify(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Text(text)),
  );
}
