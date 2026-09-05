import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/core/core_models.dart';
import 'package:maomao/src/settings/app_settings.dart';

void main() {
  test('tls fragment defaults to off', () {
    expect(const AppSettings().tlsFragment, isFalse);
    expect(AppSettings.fromJson(const {}).tlsFragment, isFalse);
  });

  test('tls fragment survives a persistence round trip', () {
    final stored = const AppSettings(tlsFragment: true).toJson();

    expect(stored['tlsFragment'], isTrue);
    expect(AppSettings.fromJson(stored).tlsFragment, isTrue);
  });

  test('start request forwards tls fragment to the core', () {
    final args = const StartRequest(
      configPath: '/tmp/config.json',
      engine: CoreEngine.singbox,
      tlsFragment: true,
    ).toArguments();

    expect(args['tlsFragment'], isTrue);
  });
}
