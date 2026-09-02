import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../api/controller_models.dart';
import '../core/core_models.dart';
import '../core/core_providers.dart';
import 'format.dart';

/// Connections and logs, the two live diagnostic views.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: l10n.tabConnections),
              Tab(text: l10n.tabLogs),
            ],
          ),
          const Expanded(
            child: TabBarView(children: [_ConnectionsTab(), _LogsTab()]),
          ),
        ],
      ),
    );
  }
}

class _ConnectionsTab extends ConsumerWidget {
  const _ConnectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot =
        ref.watch(connectionsProvider).valueOrNull ??
        const ConnectionSnapshot.empty();

    if (snapshot.connections.isEmpty) {
      return Center(child: Text(l10n.connectionsEmpty));
    }

    final items = [...snapshot.connections]
      ..sort(
        (a, b) => (b.start ?? DateTime(0)).compareTo(a.start ?? DateTime(0)),
      );

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextButton.icon(
              icon: const Icon(Icons.close),
              label: Text(l10n.closeAllConnections),
              onPressed: () => ref
                  .read(controllerClientProvider)
                  .valueOrNull
                  ?.closeAllConnections(),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _ConnectionTile(item: items[index]),
          ),
        ),
      ],
    );
  }
}

class _ConnectionTile extends ConsumerWidget {
  const _ConnectionTile({required this.item});

  final ConnectionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    dense: true,
    title: Text(
      item.metadata.target,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${item.metadata.network.toUpperCase()} · ${item.chains.join(' → ')}\n'
      '↑ ${formatBytes(item.upload)}  ↓ ${formatBytes(item.download)}',
    ),
    isThreeLine: true,
    trailing: IconButton(
      icon: const Icon(Icons.link_off, size: 20),
      tooltip: AppLocalizations.of(context).actionClose,
      onPressed: () => ref
          .read(controllerClientProvider)
          .valueOrNull
          ?.closeConnection(item.id),
    ),
  );
}

class _LogsTab extends ConsumerWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logBufferProvider).valueOrNull ?? const <LogEntry>[];
    if (logs.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).logsEmpty));
    }

    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final entry = logs[index];
        return ListTile(
          dense: true,
          leading: Text(
            formatTimestamp(entry.time),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          title: Text(entry.payload),
          textColor: switch (entry.level) {
            LogLevel.error => Theme.of(context).colorScheme.error,
            LogLevel.warning => Theme.of(context).colorScheme.tertiary,
            _ => null,
          },
        );
      },
    );
  }
}
