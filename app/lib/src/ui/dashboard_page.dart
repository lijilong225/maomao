import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core_models.dart';
import '../core/core_providers.dart';
import '../profile/profile_providers.dart';
import '../tunnel/tunnel_controller.dart';
import 'format.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coreState =
        ref.watch(coreStateProvider).valueOrNull ?? CoreState.stopped;
    final status = ref.watch(tunnelControllerProvider);
    final traffic = ref.watch(trafficProvider).valueOrNull ?? const Traffic.zero();
    final profile = ref.watch(profileControllerProvider).active;

    ref.listen(tunnelControllerProvider, (_, next) {
      final error = next.error;
      if (error == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      ref.read(tunnelControllerProvider.notifier).clearError();
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConnectionCard(
          state: coreState,
          busy: status.busy,
          profileName: profile?.name,
          onToggle: profile == null
              ? null
              : () => ref.read(tunnelControllerProvider.notifier).toggle(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: Icons.upload,
                label: 'Upload',
                value: formatRate(traffic.up),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                icon: Icons.download,
                label: 'Download',
                value: formatRate(traffic.down),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _TotalsCard(),
        const SizedBox(height: 16),
        const _CoreInfoCard(),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.state,
    required this.busy,
    required this.profileName,
    required this.onToggle,
  });

  final CoreState state;
  final bool busy;
  final String? profileName;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = state.isActive;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            IconButton.filled(
              iconSize: 56,
              padding: const EdgeInsets.all(20),
              onPressed: busy ? null : onToggle,
              style: IconButton.styleFrom(
                backgroundColor: active ? scheme.primary : scheme.surfaceContainerHighest,
                foregroundColor: active ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 56,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Icon(active ? Icons.shield : Icons.shield_outlined),
            ),
            const SizedBox(height: 16),
            Text(
              switch (state) {
                CoreState.running => 'Connected',
                CoreState.starting => 'Connecting…',
                CoreState.stopped => 'Disconnected',
              },
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              profileName ?? 'No profile selected',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _TotalsCard extends ConsumerWidget {
  const _TotalsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(connectionsProvider).valueOrNull;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Session total'),
            subtitle: Text(
              snapshot == null
                  ? '—'
                  : '↑ ${formatBytes(snapshot.uploadTotal)}   '
                        '↓ ${formatBytes(snapshot.downloadTotal)}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lan_outlined),
            title: const Text('Active connections'),
            subtitle: Text('${snapshot?.connections.length ?? 0}'),
          ),
        ],
      ),
    );
  }
}

class _CoreInfoCard extends ConsumerWidget {
  const _CoreInfoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(coreVersionProvider);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.memory),
        title: const Text('Core'),
        subtitle: Text(
          version.when(
            data: (value) => 'mihomo $value',
            loading: () => 'loading…',
            error: (error, _) => 'unavailable',
          ),
        ),
      ),
    );
  }
}
