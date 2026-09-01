import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/l10n/app_localizations.dart';
import 'package:maomao/src/ui/app.dart';

void main() {
  testWidgets('renders the five-tab shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaomaoApp()));
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.titleDashboard), findsOneWidget);
    expect(find.text(l10n.navProxies), findsOneWidget);
    expect(find.text(l10n.navSettings), findsOneWidget);
  });

  testWidgets('switches to Simplified Chinese', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(l10n.navSettings, '设置');
    expect(find.text(l10n.navSettings), findsOneWidget);
  });
}
