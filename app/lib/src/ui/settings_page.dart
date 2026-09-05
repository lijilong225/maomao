import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../core/core_models.dart';
import '../core/core_providers.dart';
import '../core/geo_assets.dart';
import '../settings/app_settings.dart';
import '../settings/release_checker.dart';
import '../settings/settings_providers.dart';
import '../tunnel/tunnel_controller.dart';
import 'format.dart';

/// Display name for each supported locale, shown in its own language.
const _localeNames = {'en': 'English', 'zh': '简体中文'};

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final running =
        (ref.watch(coreStateProvider).valueOrNull ?? CoreState.stopped) ==
        CoreState.running;

    return ListView(
      children: [
        _SectionHeader(l10n.sectionAppearance),
        ListTile(
          title: Text(l10n.language),
          subtitle: Text(
            settings.locale == null
                ? l10n.languageSystem
                : _localeNames[settings.locale!.languageCode] ??
                      settings.locale!.languageCode,
          ),
          trailing: DropdownButton<String>(
            value: settings.locale?.languageCode ?? '',
            onChanged: (tag) => controller.setLocale(
              tag == null || tag.isEmpty ? null : Locale(tag),
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(l10n.languageSystem)),
              for (final locale in supportedLocales)
                DropdownMenuItem(
                  value: locale.languageCode,
                  child: Text(
                    _localeNames[locale.languageCode] ?? locale.languageCode,
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        _SectionHeader(l10n.sectionCore),
        ListTile(
          title: Text(l10n.coreEngine),
          subtitle: Text(
            running ? l10n.coreEngineReconnect : l10n.coreEngineSubtitle,
          ),
          trailing: DropdownButton<CoreEngine>(
            value: settings.engine,
            onChanged: (engine) =>
                engine == null ? null : controller.setEngine(engine),
            items: [
              for (final engine in CoreEngine.values)
                DropdownMenuItem(value: engine, child: Text(engine.wireName)),
            ],
          ),
        ),
        const Divider(),
        _SectionHeader(l10n.sectionTunnel),
        ListTile(
          title: Text(l10n.tunStack),
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
        // IPv6 and route exclusions are applied while building the Android
        // VpnService tunnel; elsewhere the core owns the interface.
        if (Platform.isAndroid) ...[
          SwitchListTile(
            title: Text(l10n.ipv6),
            subtitle: Text(l10n.ipv6Subtitle),
            value: settings.ipv6,
            onChanged: controller.setIpv6,
          ),
          SwitchListTile(
            title: Text(l10n.bypassPrivateRoutes),
            subtitle: Text(l10n.bypassPrivateRoutesSubtitle),
            value: settings.bypassPrivateRoutes,
            onChanged: controller.setBypassPrivateRoutes,
          ),
        ],
        const Divider(),
        // Per-app proxying is backed by VpnService, an Android capability.
        if (Platform.isAndroid) ...[
          _SectionHeader(l10n.sectionPerAppProxy),
          ListTile(
            title: Text(l10n.tunnelledApps),
            subtitle: Text(
              settings.allowedApps.isEmpty
                  ? l10n.allApps
                  : l10n.appsSelected(settings.allowedApps.length),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const _AppPickerPage())),
          ),
          const Divider(),
        ],
        _SectionHeader(l10n.sectionProfiles),
        SwitchListTile(
          title: Text(l10n.updateOnLaunch),
          subtitle: Text(l10n.updateOnLaunchSubtitle),
          value: settings.autoUpdateOnLaunch,
          onChanged: controller.setAutoUpdateOnLaunch,
        ),
        ListTile(
          title: Text(l10n.globalOverride),
          subtitle: Text(
            settings.overrideYaml.isEmpty
                ? l10n.overrideNone
                : l10n.overrideLines(settings.overrideYaml.split('\n').length),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _OverrideEditorPage()),
          ),
        ),
        const Divider(),
        _SectionHeader(l10n.sectionDiagnostics),
        // sing-box configs generated by the core carry no geo rules, and it has
        // no endpoint to refresh the databases.
        if (settings.engine.supportsProviders)
          ListTile(
            title: Text(l10n.geoAssets),
            subtitle: Text(l10n.geoAssetsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const _GeoAssetsPage())),
          ),
        ListTile(
          title: Text(l10n.logLevel),
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
              label: Text(l10n.applyToRunningTunnel),
              onPressed: () => ref
                  .read(tunnelControllerProvider.notifier)
                  .applyConfigChanges(),
            ),
          ),
        const Divider(),
        _SectionHeader(l10n.sectionAbout),
        const _UpdateTile(),
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
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _AppPickerPage extends ConsumerWidget {
  const _AppPickerPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final apps = ref.watch(installedAppsProvider);
    final selected = ref.watch(settingsControllerProvider).allowedApps.toSet();
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tunnelledApps),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: l10n.tunnelAllApps,
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.globalOverride),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: l10n.actionSave,
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
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
            hintText: 'mode: rule\nlog-level: info',
            helperText: l10n.overrideHelper,
          ),
        ),
      ),
    );
  }
}

class _GeoAssetsPage extends ConsumerStatefulWidget {
  const _GeoAssetsPage();

  @override
  ConsumerState<_GeoAssetsPage> createState() => _GeoAssetsPageState();
}

class _GeoAssetsPageState extends ConsumerState<_GeoAssetsPage> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(controllerClientProvider).valueOrNull != null;
    final assets = ref.watch(geoAssetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.geoAssets),
        actions: [
          if (_updating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.geoAssetsUpdate,
              onPressed: _update,
            ),
        ],
      ),
      body: ListView(
        children: [
          if (!live)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                l10n.geoAssetsRequireCore,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final asset in assets.valueOrNull ?? const <GeoAsset>[])
            ListTile(
              title: Text(asset.name),
              subtitle: Text(
                asset.exists
                    ? '${formatBytes(asset.size)} · ${l10n.profileUpdated(formatRelative(l10n, asset.updatedAt))}'
                    : l10n.geoAssetMissing,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _update() async {
    final client = ref.read(controllerClientProvider).valueOrNull;
    final l10n = AppLocalizations.of(context);
    if (client == null) {
      _notify(l10n.geoAssetsRequireCore);
      return;
    }
    setState(() => _updating = true);
    try {
      await client.updateGeoDatabases();
      ref.invalidate(geoAssetsProvider);
      if (mounted) _notify(l10n.geoAssetsUpdated);
    } catch (error) {
      if (mounted) _notify('$error');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _UpdateTile extends ConsumerStatefulWidget {
  const _UpdateTile();

  @override
  ConsumerState<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<_UpdateTile> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final version =
        ref.watch(appVersionProvider).valueOrNull ?? fallbackAppVersion;
    return ListTile(
      title: Text(l10n.checkForUpdates),
      subtitle: Text(l10n.currentVersion(version)),
      trailing: _checking
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _checking ? null : _check,
    );
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref.read(releaseCheckerProvider).check();
      if (!mounted) return;
      if (!result.hasUpdate) {
        _notify(l10n.updateUpToDate);
        return;
      }
      await _promptDownload(l10n, result);
    } catch (error) {
      if (mounted) _notify(l10n.updateCheckFailed('$error'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _promptDownload(
    AppLocalizations l10n,
    UpdateCheck result,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.updateAvailable),
        content: Text(l10n.updateAvailableBody(result.latestVersion!)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.updateDownload),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final opened = await launchUrl(
      Uri.parse(result.url ?? releasesPageUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) _notify(releasesPageUrl);
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}
