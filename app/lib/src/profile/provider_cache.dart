import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'config_outline.dart';

/// Reads the bodies the core keeps on disk for `proxy-providers` and
/// `rule-providers`.
///
/// The core's home directory is `<filesDir>/core` (set by the Android side),
/// which is where `path_provider`'s application support directory points, and it
/// stores a downloaded provider as `<section>/<md5 hex of url>`. Reading those
/// files lets the proxy pages list providers and group members while the tunnel
/// is down.
class ProviderCache {
  const ProviderCache({this.homeDir});

  /// Overrides the core home directory in tests.
  final Directory? homeDir;

  Future<Map<String, String>> read(Iterable<ConfigProviderRef> refs) async {
    if (refs.isEmpty) return const {};
    final home = homeDir ?? await _coreHome();

    final bodies = <String, String>{};
    for (final ref in refs) {
      final file = _fileFor(ref, home);
      if (file == null) continue;
      try {
        if (await file.exists()) bodies[ref.name] = await file.readAsString();
      } on FileSystemException {
        // Unreadable cache is equivalent to a provider that never synced.
      }
    }
    return bodies;
  }

  /// Body plus modification time of each cached provider, keyed by name.
  ///
  /// The core does not persist its own `updatedAt` for a provider, so the file
  /// timestamp is the only offline stand-in for it.
  Future<Map<String, CachedProvider>> readWithStat(
    Iterable<ConfigProviderRef> refs,
  ) async {
    if (refs.isEmpty) return const {};
    final home = homeDir ?? await _coreHome();

    final cached = <String, CachedProvider>{};
    for (final ref in refs) {
      final file = _fileFor(ref, home);
      if (file == null) continue;
      try {
        if (!await file.exists()) continue;
        cached[ref.name] = CachedProvider(
          // A rule set in `mrs` format is a binary bundle, so decoding is
          // lenient: only its timestamp is of any use then.
          body: utf8.decode(await file.readAsBytes(), allowMalformed: true),
          updatedAt: (await file.stat()).modified,
        );
      } on FileSystemException {
        // Unreadable cache is equivalent to a provider that never synced.
      }
    }
    return cached;
  }

  static Future<Directory> _coreHome() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/core');

  File? _fileFor(ConfigProviderRef ref, Directory home) {
    final path = ref.path;
    if (path != null && path.isNotEmpty) {
      return File(path.startsWith('/') ? path : '${home.path}/$path');
    }
    final url = ref.url;
    if (ref.type != 'http' || url == null || url.isEmpty) return null;
    final hash = md5.convert(utf8.encode(url));
    return File('${home.path}/${ref.section.cachePrefix}/$hash');
  }
}

/// A provider body the core already downloaded.
class CachedProvider {
  const CachedProvider({required this.body, required this.updatedAt});

  final String body;
  final DateTime updatedAt;
}
