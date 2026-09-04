import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/l10n/app_localizations.dart';
import 'package:maomao/src/api/controller_models.dart';
import 'package:maomao/src/core/core_providers.dart';
import 'package:maomao/src/profile/latency_probe.dart';
import 'package:maomao/src/profile/profile_providers.dart';
import 'package:maomao/src/ui/proxies_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers instantly so the widget test never opens a socket.
class _FakeProbe extends LatencyProbe {
  const _FakeProbe(this.result);

  final int result;

  @override
  Future<int> measure(String host, int port) async => result;
}

ProxySnapshot _snapshot() {
  const member = ProxyNode(
    name: 'node-a',
    type: 'Shadowsocks',
    udp: false,
    history: [],
    server: '127.0.0.1',
    port: 1080,
  );
  const group = ProxyNode(
    name: 'Proxy',
    type: 'Selector',
    udp: false,
    history: [],
    now: 'node-a',
    all: ['node-a'],
  );
  return const ProxySnapshot(
    nodes: {'node-a': member, 'Proxy': group},
    groups: [group],
  );
}

Future<void> _pumpPage(WidgetTester tester, int measured) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        controllerClientProvider.overrideWith((ref) => Stream.value(null)),
        activeProfileOutlineProvider.overrideWith((ref) => _snapshot()),
        offlineLatencyProvider.overrideWith(
          (ref) => OfflineLatencyController(_FakeProbe(measured)),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ProxiesPage()),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Proxy'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('measures a single node when its delay area is tapped', (
    tester,
  ) async {
    await _pumpPage(tester, 42);
    expect(find.text('—'), findsOneWidget);

    await tester.tap(find.text('—'));
    // No pumpAndSettle: the spinner shown mid-test never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('42 ms'), findsOneWidget);
  });

  testWidgets('names a member that refused the handshake', (tester) async {
    await _pumpPage(tester, 0);

    await tester.tap(find.text('—'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.nodeUnreachable), findsOneWidget);
  });
}
