import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profile/profile_providers.dart';
import '../settings/settings_providers.dart';
import 'activity_page.dart';
import 'dashboard_page.dart';
import 'profiles_page.dart';
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

  static const _titles = [
    'Dashboard',
    'Proxies',
    'Profiles',
    'Activity',
    'Settings',
  ];

  static const _pages = [
    DashboardPage(),
    ProxiesPage(),
    ProfilesPage(),
    ActivityPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_titles[_index])),
    body: _pages[_index],
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.speed_outlined),
          selectedIcon: Icon(Icons.speed),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.hub_outlined),
          selectedIcon: Icon(Icons.hub),
          label: 'Proxies',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: 'Profiles',
        ),
        NavigationDestination(
          icon: Icon(Icons.list_alt_outlined),
          selectedIcon: Icon(Icons.list_alt),
          label: 'Activity',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    ),
  );
}

class MaomaoApp extends ConsumerWidget {
  const MaomaoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'maomao',
    debugShowCheckedModeBanner: false,
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
