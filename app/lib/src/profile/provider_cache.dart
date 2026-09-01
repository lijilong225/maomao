import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'config_outline.dart';

/// Reads the node lists the core keeps on disk for `proxy-providers`.
///
/// The core's home directory is `<filesDir>/core` (set by the Android side),
/// which is where `path_provider`'s application support directory points, and it
/// stores a downloaded provider as `proxies/<md5 hex of url>`. Reading those
/// files lets the proxy page list group members while the tunnel is down.
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

  static Future<Directory> _coreHome() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/core');

  File? _fileFor(ConfigProviderRef ref, Directory home) {
    final path = ref.path;
    if (path != null && path.isNotEmpty) {
      return File(path.startsWith('/') ? path : '${home.path}/$path');
    }
    final url = ref.url;
    if (ref.type != 'http' || url == null || url.isEmpty) return null;
    return File('${home.path}/proxies/${md5.convert(utf8.encode(url))}');
  }
}
