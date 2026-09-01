import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/core/geo_assets.dart';

void main() {
  test('lists geo databases with size and modification time', () async {
    final home = await Directory.systemTemp.createTemp('geo_assets');
    addTearDown(() => home.delete(recursive: true));
    await File('${home.path}/GeoSite.dat').writeAsBytes(List.filled(12, 0));
    await File('${home.path}/runtime.yaml').writeAsString('mode: rule');

    final assets = await GeoAssetRepository(homeDir: home).list();

    expect(assets.map((a) => a.name), ['GeoSite.dat']);
    expect(assets.single.size, 12);
    expect(assets.single.exists, isTrue);
  });

  test('falls back to placeholders when nothing was downloaded', () async {
    final home = await Directory.systemTemp.createTemp('geo_assets_empty');
    addTearDown(() => home.delete(recursive: true));

    final assets = await GeoAssetRepository(homeDir: home).list();

    expect(assets.map((a) => a.name), ['GeoIP.dat', 'GeoSite.dat']);
    expect(assets.every((a) => !a.exists), isTrue);
  });
}
