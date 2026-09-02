import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/settings/release_checker.dart';

void main() {
  test('compares dotted versions regardless of decoration', () {
    expect(isNewerRelease('v1.0.1', '1.0.0'), isTrue);
    expect(isNewerRelease('1.2.0', '1.10.0'), isFalse);
    expect(isNewerRelease('v1.0.0', '1.0.0+7'), isFalse);
    expect(isNewerRelease('v2.0', '1.9.9'), isTrue);
    expect(isNewerRelease('nightly', '1.0.0'), isFalse);
  });

  test('keeps the compiled-in fallback aligned with pubspec', () {
    final declared = RegExp(
      r'^version:\s*([^\s+]+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())?.group(1);

    expect(declared, isNotNull);
    expect(fallbackAppVersion, declared);
  });
}
