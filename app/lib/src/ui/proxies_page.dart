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
                    '${l10n.proxiesPreviewOnly} ${l10n.reachabilityHint}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              final group = groups[live ? index : index - 1];
              return _GroupTile(
                // Keyed so the per-node spinners stay with their own group when
                // a refresh reorders the list.
                key: ValueKey(group.name),
                group: group,
                nodes: data.nodes,
                live: live,
              );
            },
          ),
        );
      },
    );
  }
}

class _GroupTile extends ConsumerStatefulWidget {
  const _GroupTile({
    super.key,
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
  bool _testingGroup = false;

  /// Members being measured on their own, so each row can spin independently.
  final _testingNodes = <String>{};

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
        trailing: _testingGroup
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
                tooltip: widget.live ? l10n.testLatency : l10n.testReachability,
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
              trailing: _memberDelay(member, measured, l10n),
              onTap: _canSelect ? () => _select(member) : null,
            ),
        ],
      ),
    );
  }

  /// Nothing for a member the app cannot dial itself, such as DIRECT or a
  /// nested group; otherwise a readout that measures this member when tapped.
  Widget? _memberDelay(
    String member,
    Map<String, int> measured,
    AppLocalizations l10n,
  ) {
    final offlineOnly = !widget.live;
    if (offlineOnly && !(widget.nodes[member]?.hasEndpoint ?? false)) {
      return null;
    }
    final delay = offlineOnly
        ? measured[member]
        : widget.nodes[member]?.latestDelay ?? 0;
    final testing = _testingNodes.contains(member);
    return _NodeDelay(
      // Offline a measured 0 means the server refused, which is worth naming;
      // the core instead records 0 for anything it has not tested yet.
      label: offlineOnly && delay == 0
          ? l10n.nodeUnreachable
          : formatDelay(delay ?? 0),
      tooltip: widget.live ? l10n.testLatency : l10n.testReachability,
      testing: testing,
      onTest: () => _testNode(member),
    );
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
    if (_testingGroup) return;
    setState(() => _testingGroup = true);
    try {
      await (widget.live ? _testViaCore() : _testEndpoints());
    } finally {
      if (mounted) setState(() => _testingGroup = false);
    }
  }

  Future<void> _testNode(String member) async {
    if (_testingNodes.contains(member)) return;
    setState(() => _testingNodes.add(member));
    try {
      await (widget.live
          ? _testNodeViaCore(member)
          : _testNodeEndpoint(member));
    } finally {
      if (mounted) setState(() => _testingNodes.remove(member));
    }
  }

  Future<void> _testNodeViaCore(String member) async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null) return;
    try {
      await client.proxyDelay(member);
      ref.invalidate(proxiesProvider);
    } catch (_) {
      // A timeout is recorded as 0, which reads the same as "never tested".
      if (mounted) {
        _notify(AppLocalizations.of(context).nodeTestFailed(member));
      }
    }
  }

  Future<void> _testNodeEndpoint(String member) {
    final node = widget.nodes[member];
    if (node == null) return Future.value();
    return ref.read(offlineLatencyProvider.notifier).measureAll([node]);
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

  /// Dials the members' servers directly; each row reports its own outcome.
  Future<void> _testEndpoints() =>
      ref.read(offlineLatencyProvider.notifier).measureAll([
        for (final member in group.all)
          if (widget.nodes[member] != null) widget.nodes[member]!,
      ]);

  void _notify(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

/// Latency readout of one node that measures that node when tapped.
class _NodeDelay extends StatelessWidget {
  const _NodeDelay({
    required this.label,
    required this.tooltip,
    required this.testing,
    required this.onTest,
  });

  final String label;
  final String tooltip;
  final bool testing;

  /// Always set, so a tap on this region never falls through to the row's own
  /// selection handler.
  final VoidCallback onTest;

  static const _fade = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTest,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        // Fixed so swapping the readout for the spinner does not shift the row.
        width: 88,
        height: 40,
        child: Center(
          child: AnimatedSwitcher(
            duration: _fade,
            child: testing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    label,
                    key: ValueKey(label),
                    maxLines: 1,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Text(text)),
  );
}
