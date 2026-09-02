import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/profile/config_outline.dart';
import 'package:maomao/src/profile/provider_cache.dart';

void main() {
  test('reads each section from its own cache directory', () async {
    final home = await Directory.systemTemp.createTemp('provider_cache');
    addTearDown(() => home.delete(recursive: true));

    const proxyUrl = 'https://example.com/sub';
    const ruleUrl = 'https://example.com/ads.yaml';
    await _write(home, 'proxies', proxyUrl, 'proxies: []');
    await _write(home, 'rules', ruleUrl, 'payload: []');

    final cache = ProviderCache(homeDir: home);
    final proxies = await cache.readWithStat([
      const ConfigProviderRef(
        section: ProviderSection.proxies,
        name: 'remote',
        type: 'http',
        url: proxyUrl,
      ),
    ]);
    final rules = await cache.readWithStat([
      const ConfigProviderRef(
        section: ProviderSection.rules,
        name: 'ads',
        type: 'http',
        url: ruleUrl,
      ),
      // Never downloaded, so it must stay out of the result.
      const ConfigProviderRef(
        section: ProviderSection.rules,
        name: 'missing',
        type: 'http',
        url: 'https://example.com/none.yaml',
      ),
    ]);

    expect(proxies['remote']?.body, 'proxies: []');
    expect(rules.keys, ['ads']);
    expect(rules['ads']?.body, 'payload: []');
    expect(rules['ads']?.updatedAt, isNotNull);
  });

  test('keeps a binary rule set readable enough to timestamp', () async {
    final home = await Directory.systemTemp.createTemp('provider_cache_mrs');
    addTearDown(() => home.delete(recursive: true));

    const url = 'https://example.com/ads.mrs';
    final file = File('${home.path}/rules/${md5.convert(utf8.encode(url))}');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([0x4d, 0x52, 0x53, 0xff, 0xfe]);

    final cached = await ProviderCache(homeDir: home).readWithStat([
      const ConfigProviderRef(
        section: ProviderSection.rules,
        name: 'ads',
        type: 'http',
        url: url,
        format: 'mrs',
      ),
    ]);

    expect(cached['ads']?.updatedAt, isNotNull);
  });

  test('writes a downloaded body where the core reads it', () async {
    final home = await Directory.systemTemp.createTemp('provider_cache_write');
    addTearDown(() => home.delete(recursive: true));

    const url = 'https://example.com/ads.yaml';
    const ref = ConfigProviderRef(
      section: ProviderSection.rules,
      name: 'ads',
      type: 'http',
      url: url,
    );

    final cache = ProviderCache(homeDir: home);
    await cache.write(ref, utf8.encode('payload: [example.com]'));

    final expected = File(
      '${home.path}/rules/${md5.convert(utf8.encode(url))}',
    );
    expect(expected.existsSync(), isTrue);
    final cached = await cache.readWithStat([ref]);
    expect(cached['ads']?.body, 'payload: [example.com]');
    expect(cached['ads']?.updatedAt, isNotNull);
  });

  test('refuses to write a provider it cannot download', () async {
    final home = await Directory.systemTemp.createTemp('provider_cache_deny');
    addTearDown(() => home.delete(recursive: true));

    final cache = ProviderCache(homeDir: home);

    // Supplied by the user, so the app has nothing to download.
    await expectLater(
      cache.write(
        const ConfigProviderRef(
          section: ProviderSection.rules,
          name: 'local',
          type: 'file',
          path: 'rules/local.yaml',
        ),
        const [0x00],
      ),
      throwsA(isA<FileSystemException>()),
    );

    // A path out of the core home must not steer the write.
    await expectLater(
      cache.write(
        const ConfigProviderRef(
          section: ProviderSection.rules,
          name: 'escape',
          type: 'http',
          url: 'https://example.com/ads.yaml',
          path: '../../escaped.yaml',
        ),
        const [0x00],
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}

Future<void> _write(
  Directory home,
  String prefix,
  String url,
  String body,
) async {
  final file = File('${home.path}/$prefix/${md5.convert(utf8.encode(url))}');
  await file.parent.create(recursive: true);
  await file.writeAsString(body);
}
