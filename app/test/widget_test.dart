import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/ui/app.dart';

void main() {
  testWidgets('renders the five-tab shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaomaoApp()));
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Proxies'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
