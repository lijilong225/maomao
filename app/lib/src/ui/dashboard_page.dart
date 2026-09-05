import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../core/core_models.dart';
import '../core/core_providers.dart';
import '../profile/profile_providers.dart';
import '../settings/settings_providers.dart';
import '../tunnel/tunnel_controller.dart';
import 'format.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final coreState =
        ref.watch(coreStateProvider).valueOrNull ?? CoreState.stopped;
    final status = ref.watch(tunnelControllerProvider);
    final traffic =
        ref.watch(trafficProvider).valueOrNull ?? const Traffic.zero();
    final profile = ref.watch(profileControllerProvider).active;

    ref.listen(tunnelControllerProvider, (_, next) {
      final error = next.error;
      if (error == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
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
                label: l10n.trafficUpload,
                value: formatRate(traffic.up),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                icon: Icons.download,
                label: l10n.trafficDownload,
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

  static const _transition = Duration(milliseconds: 280);

  final CoreState state;
  final bool busy;
  final String? profileName;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onToggle != null;

    // `starting` gets its own colours so a tap reads as acknowledged well before
    // the tunnel is actually up.
    final (background, foreground) = switch (enabled ? state : null) {
      CoreState.running => (scheme.primary, scheme.onPrimary),
      CoreState.starting => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      CoreState.stopped => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      null => (scheme.surfaceContainerHighest, theme.disabledColor),
    };
    final pending = busy || state == CoreState.starting;
    final label = switch (state) {
      CoreState.running => l10n.stateConnected,
      CoreState.starting => l10n.stateConnecting,
      CoreState.stopped => l10n.stateDisconnected,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox.square(
              dimension: 104,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: _transition,
                    child: pending
                        ? SizedBox.square(
                            dimension: 104,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: scheme.primary,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  AnimatedContainer(
                    duration: _transition,
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: background,
                      shape: BoxShape.circle,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: busy ? null : onToggle,
                        child: SizedBox.square(
                          dimension: 88,
                          child: Center(
                            child: TweenAnimationBuilder<Color?>(
                              duration: _transition,
                              tween: ColorTween(end: foreground),
                              builder: (context, color, _) => AnimatedSwitcher(
                                duration: _transition,
                                child: Icon(
                                  state == CoreState.running
                                      ? Icons.shield
                                      : Icons.shield_outlined,
                                  key: ValueKey(state == CoreState.running),
                                  size: 44,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: _transition,
              child: Text(
                label,
                key: ValueKey(label),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              profileName ?? l10n.noProfileSelected,
              style: theme.textTheme.bodyMedium,
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
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(connectionsProvider).valueOrNull;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: Text(l10n.sessionTotal),
            subtitle: Text(
              snapshot == null
                  ? '—'
                  : '↑ ${formatBytes(snapshot.uploadTotal)}   '
                        '↓ ${formatBytes(snapshot.downloadTotal)}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lan_outlined),
            title: Text(l10n.activeConnections),
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
    final l10n = AppLocalizations.of(context);
    final engine = ref.watch(coreEngineProvider);
    final version = ref.watch(coreVersionProvider);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.memory),
        title: Text(l10n.coreLabel),
        subtitle: Text(
          version.when(
            data: (value) => l10n.coreVersion(engine.wireName, value),
            loading: () => l10n.loading,
            error: (error, _) => l10n.unavailable,
          ),
        ),
      ),
    );
  }
}
