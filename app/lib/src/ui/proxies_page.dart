import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/controller_models.dart';
import '../core/core_providers.dart';
import 'format.dart';

class ProxiesPage extends ConsumerWidget {
  const ProxiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxies = ref.watch(proxiesProvider);

    return proxies.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(text: 'Unavailable: $error'),
      data: (nodes) {
        final groups = nodes.values.where((node) => node.isGroup).toList();
        if (groups.isEmpty) {
          return const _Message(text: 'Connect to load policy groups.');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(proxiesProvider),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, index) =>
                _GroupTile(group: groups[index], nodes: nodes),
          ),
        );
      },
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group, required this.nodes});

  final ProxyNode group;
  final Map<String, ProxyNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: ExpansionTile(
      title: Text(group.name),
      subtitle: Text('${group.type} · ${group.now ?? '—'}'),
      trailing: IconButton(
        icon: const Icon(Icons.speed),
        tooltip: 'Test latency',
        onPressed: () => _testGroup(context, ref),
      ),
      children: [
        for (final member in group.all)
          ListTile(
            dense: true,
            enabled: group.isSelectable,
            leading: Icon(
              member == group.now
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
            ),
            title: Text(member),
            trailing: Text(formatDelay(nodes[member]?.latestDelay ?? 0)),
            onTap: group.isSelectable
                ? () => _select(context, ref, member)
                : null,
          ),
      ],
    ),
  );

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    String? member,
  ) async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null || member == null) return;
    try {
      await client.selectProxy(group.name, member);
      ref.invalidate(proxiesProvider);
    } catch (error) {
      if (context.mounted) _notify(context, '$error');
    }
  }

  Future<void> _testGroup(BuildContext context, WidgetRef ref) async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    if (client == null) return;
    try {
      await client.groupDelay(group.name);
      ref.invalidate(proxiesProvider);
    } catch (error) {
      if (context.mounted) _notify(context, '$error');
    }
  }

  void _notify(BuildContext context, String message) =>
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
