import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One of the GeoIP/GeoSite database files the core keeps in its home directory.
class GeoAsset {
  const GeoAsset({
    required this.name,
    required this.size,
    required this.updatedAt,
  });

  final String name;

  /// Zero when the core has not downloaded the file yet.
  final int size;
  final DateTime? updatedAt;

  bool get exists => updatedAt != null;
}

/// Lists the geo databases by stat-ing the core home directory.
///
/// The controller API only exposes an update call, so file size and modification
/// time have to be read off disk. Names match `constant/path.go`, whose lookups
/// are case-insensitive and accept several MMDB spellings.
class GeoAssetRepository {
  const GeoAssetRepository({this.homeDir});

  /// Overrides the core home directory in tests.
  final Directory? homeDir;

  static const _names = [
    'GeoIP.dat',
    'GeoSite.dat',
    'ASN.mmdb',
    'Country.mmdb',
    'geoip.db',
    'geoip.metadb',
  ];

  Future<List<GeoAsset>> list() async {
    final home = homeDir ?? await _coreHome();
    final found = <String, FileStat>{};
    try {
      for (final entry in await home.list().toList()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        final known = _names.firstWhere(
          (candidate) => candidate.toLowerCase() == name.toLowerCase(),
          orElse: () => '',
        );
        if (known.isEmpty) continue;
        found[name] = await entry.stat();
      }
    } on FileSystemException {
      // A home directory that does not exist yet means nothing was downloaded.
    }

    if (found.isNotEmpty) {
      final names = found.keys.toList()..sort();
      return [
        for (final name in names)
          GeoAsset(
            name: name,
            size: found[name]!.size,
            updatedAt: found[name]!.modified,
          ),
      ];
    }

    // Show the two databases the core always needs so the page is never blank.
    return const [
      GeoAsset(name: 'GeoIP.dat', size: 0, updatedAt: null),
      GeoAsset(name: 'GeoSite.dat', size: 0, updatedAt: null),
    ];
  }

  static Future<Directory> _coreHome() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/core');
}
