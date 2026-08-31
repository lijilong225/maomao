import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core_models.dart';
import '../core/core_providers.dart';
import '../settings/settings_providers.dart';
import '../tunnel/tunnel_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final running =
        (ref.watch(coreStateProvider).valueOrNull ?? CoreState.stopped) ==
        CoreState.running;

    return ListView(
      children: [
        const _SectionHeader('Tunnel'),
        ListTile(
          title: const Text('TUN stack'),
          subtitle: Text(settings.tunStack.wireName),
          trailing: DropdownButton<TunStack>(
            value: settings.tunStack,
            onChanged: (stack) =>
                stack == null ? null : controller.setTunStack(stack),
            items: [
              for (final stack in TunStack.values)
                DropdownMenuItem(value: stack, child: Text(stack.wireName)),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('IPv6'),
          subtitle: const Text('Route IPv6 traffic through the tunnel'),
          value: settings.ipv6,
          onChanged: controller.setIpv6,
        ),
        SwitchListTile(
          title: const Text('Bypass private routes'),
          subtitle: const Text('Keep LAN traffic outside the tunnel'),
          value: settings.bypassPrivateRoutes,
          onChanged: controller.setBypassPrivateRoutes,
        ),
        const Divider(),
        const _SectionHeader('Per-app proxy'),
        ListTile(
          title: const Text('Tunnelled apps'),
          subtitle: Text(
            settings.allowedApps.isEmpty
                ? 'All apps'
                : '${settings.allowedApps.length} selected',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _AppPickerPage()),
          ),
        ),
        const Divider(),
        const _SectionHeader('Profiles'),
        SwitchListTile(
          title: const Text('Update on launch'),
          subtitle: const Text('Refresh subscriptions whose interval elapsed'),
          value: settings.autoUpdateOnLaunch,
          onChanged: controller.setAutoUpdateOnLaunch,
        ),
        ListTile(
          title: const Text('Global override'),
          subtitle: Text(
            settings.overrideYaml.isEmpty
                ? 'None'
                : '${settings.overrideYaml.split('\n').length} lines',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _OverrideEditorPage()),
          ),
        ),
        const Divider(),
        const _SectionHeader('Diagnostics'),
        ListTile(
          title: const Text('Log level'),
          trailing: DropdownButton<LogLevel>(
            value: settings.logLevel,
            onChanged: (level) =>
                level == null ? null : controller.setLogLevel(level),
            items: [
              for (final level in LogLevel.values)
                DropdownMenuItem(value: level, child: Text(level.name)),
            ],
          ),
        ),
        if (running)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.refresh),
              label: const Text('Apply to running tunnel'),
              onPressed: () => ref
                  .read(tunnelControllerProvider.notifier)
                  .applyConfigChanges(),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _AppPickerPage extends ConsumerWidget {
  const _AppPickerPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(installedAppsProvider);
    final selected = ref.watch(settingsControllerProvider).allowedApps.toSet();
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tunnelled apps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Tunnel all apps',
            onPressed: () => controller.setAllowedApps(const []),
          ),
        ],
      ),
      body: apps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) {
          final userApps = items.where((app) => !app.isSystem).toList();
          return ListView.builder(
            itemCount: userApps.length,
            itemBuilder: (context, index) {
              final app = userApps[index];
              return CheckboxListTile(
                title: Text(app.label),
                subtitle: Text(app.packageName),
                value: selected.contains(app.packageName),
                onChanged: (checked) {
                  final next = {...selected};
                  if (checked ?? false) {
                    next.add(app.packageName);
                  } else {
                    next.remove(app.packageName);
                  }
                  controller.setAllowedApps(next.toList());
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _OverrideEditorPage extends ConsumerStatefulWidget {
  const _OverrideEditorPage();

  @override
  ConsumerState<_OverrideEditorPage> createState() =>
      _OverrideEditorPageState();
}

class _OverrideEditorPageState extends ConsumerState<_OverrideEditorPage> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(settingsControllerProvider).overrideYaml,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Global override'),
      actions: [
        IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Save',
          onPressed: () {
            ref
                .read(settingsControllerProvider.notifier)
                .setOverrideYaml(_controller.text);
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
          hintText: 'mode: rule\nlog-level: info',
          helperText: 'YAML patch merged onto every profile',
        ),
      ),
    ),
  );
}
