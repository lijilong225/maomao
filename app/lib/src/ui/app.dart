import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../profile/profile_providers.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';
import 'activity_page.dart';
import 'dashboard_page.dart';
import 'profiles_page.dart';
import 'providers_page.dart';
import 'proxies_page.dart';
import 'settings_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(settingsControllerProvider).autoUpdateOnLaunch) return;
      ref.read(profileControllerProvider.notifier).updateStale();
    });
  }

  static const _pages = [
    DashboardPage(),
    ProxiesPage(),
    ProfilesPage(),
    ActivityPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [
      l10n.titleDashboard,
      l10n.titleProxies,
      l10n.titleProfiles,
      l10n.titleActivity,
      l10n.titleSettings,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        // sing-box has no provider concept, so the menu would only ever be empty.
        actions: [
          if (_index == 1 && ref.watch(coreEngineProvider).supportsProviders)
            const ProvidersMenuButton(),
        ],
      ),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.speed_outlined),
            selectedIcon: const Icon(Icons.speed),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.hub_outlined),
            selectedIcon: const Icon(Icons.hub),
            label: l10n.navProxies,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: l10n.navProfiles,
          ),
          NavigationDestination(
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt),
            label: l10n.navActivity,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

class MaomaoApp extends ConsumerWidget {
  const MaomaoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    debugShowCheckedModeBanner: false,
    locale: ref.watch(settingsControllerProvider).locale,
    supportedLocales: supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B6EA5)),
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B6EA5),
        brightness: Brightness.dark,
      ),
    ),
    home: const HomeShell(),
  );
}
