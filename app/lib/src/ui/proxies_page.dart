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
                    l10n.proxiesPreviewOnly,
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

  /// False while the core is down, which makes the list read-only.
  final bool live;

  @override
  ConsumerState<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends ConsumerState<_GroupTile> {
  bool _testing = false;

  ProxyNode get group => widget.group;

  bool get _canSelect => widget.live && group.isSelectable;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: ExpansionTile(
      title: Text(group.name),
      subtitle: Text('${group.type} · ${group.now ?? '—'}'),
      trailing: !widget.live
          ? null
          : _testing
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
              tooltip: AppLocalizations.of(context).testLatency,
              onPressed: _testGroup,
            ),
      children: [
        for (final member in group.all)
          ListTile(
            dense: true,
            enabled: _canSelect,
            leading: Icon(
              member == group.now
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
            ),
            title: Text(member),
            trailing: widget.live
                ? Text(formatDelay(widget.nodes[member]?.latestDelay ?? 0))
                : null,
            onTap: _canSelect ? () => _select(member) : null,
          ),
      ],
    ),
  );

  Future<void> _select(String? member) async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null || member == null) return;
    try {
      await client.selectProxy(group.name, member);
      ref.invalidate(proxiesProvider);
    } catch (error) {
      if (mounted) _notify('$error');
    }
  }

  Future<void> _testGroup() async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null || _testing) return;
    setState(() => _testing = true);
    try {
      await client.groupDelay(group.name);
      ref.invalidate(proxiesProvider);
    } catch (_) {
      // The controller answers 504 when every member times out.
      if (mounted) _notify(AppLocalizations.of(context).latencyTestFailed);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Text(text)),
  );
}
