import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Where users download builds; also the fallback when the API has no release.
const releasesPageUrl = 'https://github.com/lijilong225/maomao/releases';

const _latestReleaseApi =
    'https://api.github.com/repos/lijilong225/maomao/releases/latest';

/// Version compiled into the app, used when the platform side cannot answer.
///
/// Must stay in sync with `version:` in `pubspec.yaml`; a test enforces it.
const fallbackAppVersion = '1.0.7';

/// Installed version, falling back to [fallbackAppVersion] instead of failing.
///
/// `PackageInfo` crosses a platform channel, which throws when the plugin is
/// not attached (a stale install, an engine restarted after the plugin was
/// added). That used to make the version vanish from the UI without a trace.
Future<String> currentAppVersion() async {
  try {
    final version = (await PackageInfo.fromPlatform()).version;
    if (version.isNotEmpty) return version;
  } catch (_) {
    // Showing a slightly stale version beats showing none.
  }
  return fallbackAppVersion;
}

class UpdateCheck {
  const UpdateCheck({
    required this.currentVersion,
    this.latestVersion,
    this.url,
  });

  final String currentVersion;

  /// Null when no newer release was published.
  final String? latestVersion;
  final String? url;

  bool get hasUpdate => latestVersion != null;
}

class ReleaseChecker {
  ReleaseChecker({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'Accept': 'application/vnd.github+json'},
              responseType: ResponseType.json,
            ),
          );

  final Dio _dio;

  void close() => _dio.close(force: true);

  Future<UpdateCheck> check() async {
    final current = await currentAppVersion();
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.get<Map<String, dynamic>>(_latestReleaseApi);
    } on DioException catch (error) {
      // A repository without any published release answers 404.
      if (error.response?.statusCode == 404) {
        return UpdateCheck(currentVersion: current);
      }
      throw Exception(error.response?.statusCode ?? error.message);
    }

    final body = response.data ?? const {};
    final tag = body['tag_name'] as String? ?? '';
    if (!isNewerRelease(tag, current)) {
      return UpdateCheck(currentVersion: current);
    }
    return UpdateCheck(
      currentVersion: current,
      latestVersion: tag,
      url: body['html_url'] as String? ?? releasesPageUrl,
    );
  }
}

/// Whether the release tagged [tag] is newer than the installed [current].
///
/// Both sides may be decorated (`v1.2.3`, `1.2.3+4`, `1.2.3-beta`); only the
/// leading dotted number is compared, so undecipherable tags count as not newer.
bool isNewerRelease(String tag, String current) {
  final latest = _numbers(tag);
  if (latest.isEmpty) return false;
  final installed = _numbers(current);
  for (
    var i = 0;
    i < (latest.length > installed.length ? latest.length : installed.length);
    i++
  ) {
    final a = i < latest.length ? latest[i] : 0;
    final b = i < installed.length ? installed[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

List<int> _numbers(String raw) {
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(raw);
  if (match == null) return const [];
  return [for (final part in match[0]!.split('.')) int.parse(part)];
}
