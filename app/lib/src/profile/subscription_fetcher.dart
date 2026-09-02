import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'profile_models.dart';

class SubscriptionException implements Exception {
  SubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SubscriptionPayload {
  const SubscriptionPayload({
    required this.body,
    this.userInfo,
    this.suggestedName,
  });

  final String body;
  final SubscriptionUserInfo? userInfo;
  final String? suggestedName;
}

/// Downloads subscription bodies with the checks a user-supplied URL demands.
///
/// A subscription URL is untrusted input that the app fetches on the user's
/// behalf, so it is treated as an SSRF vector: https only, resolved addresses
/// must be public, redirects are followed manually and re-validated, and the
/// body is capped.
class SubscriptionFetcher {
  SubscriptionFetcher({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              followRedirects: false,
              validateStatus: (status) => status != null && status < 400,
              responseType: ResponseType.stream,
            ),
          );

  final Dio _dio;

  static const maxBodyBytes = 16 * 1024 * 1024;
  static const maxRedirects = 5;
  static const userAgent = 'maomao/1.0 (clash-meta; mihomo)';

  void close() => _dio.close(force: true);

  Future<SubscriptionPayload> fetch(String rawUrl) async {
    final response = await _fetch(rawUrl);
    return SubscriptionPayload(
      body: _decode(await _readBytes(response)),
      userInfo: SubscriptionUserInfo.parseHeader(
        response.headers.value('subscription-userinfo'),
      ),
      suggestedName: _filename(response.headers.value('content-disposition')),
    );
  }

  /// Raw body of [rawUrl], fetched under the same checks as [fetch].
  ///
  /// A rule set in `mrs` format is a binary bundle, so it must reach the caller
  /// undecoded.
  Future<Uint8List> fetchBytes(String rawUrl) async =>
      _readBytes(await _fetch(rawUrl));

  /// Final response of [rawUrl], with its body still unread.
  Future<Response<ResponseBody>> _fetch(String rawUrl) async {
    var target = _validateUrl(rawUrl);

    for (var hop = 0; hop <= maxRedirects; hop++) {
      await _assertPublicHost(target.host);

      final response = await _get(target);
      final location = response.headers.value(HttpHeaders.locationHeader);

      if (_isRedirect(response.statusCode) && location != null) {
        await _drain(response);
        target = _validateUrl(target.resolve(location).toString());
        continue;
      }

      return response;
    }

    throw SubscriptionException('Too many redirects (>$maxRedirects)');
  }

  Future<Response<ResponseBody>> _get(Uri url) async {
    try {
      final response = await _dio.getUri<ResponseBody>(
        url,
        options: Options(headers: {HttpHeaders.userAgentHeader: userAgent}),
      );
      if (response.data == null) {
        throw SubscriptionException('Empty response from ${url.host}');
      }
      return response;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      throw SubscriptionException(
        status != null
            ? 'Subscription request failed with HTTP $status'
            : 'Subscription request failed: ${e.message ?? e.type.name}',
      );
    }
  }

  Future<Uint8List> _readBytes(Response<ResponseBody> response) async {
    final declared = int.tryParse(
      response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
    );
    if (declared != null && declared > maxBodyBytes) {
      await _drain(response);
      throw SubscriptionException(
        'Subscription is larger than ${maxBodyBytes ~/ (1024 * 1024)} MiB',
      );
    }

    final builder = BytesBuilder(copy: false);
    // Enforced while streaming too, since Content-Length may be absent or lie.
    await for (final chunk in response.data!.stream) {
      builder.add(chunk);
      if (builder.length > maxBodyBytes) {
        throw SubscriptionException(
          'Subscription is larger than ${maxBodyBytes ~/ (1024 * 1024)} MiB',
        );
      }
    }

    return builder.takeBytes();
  }

  static String _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw SubscriptionException('Subscription body is not valid UTF-8');
    }
  }

  Future<void> _drain(Response<ResponseBody> response) async {
    try {
      await response.data?.stream.drain<void>();
    } catch (_) {
      // The body is irrelevant here; failing to drain must not mask the outcome.
    }
  }

  static bool _isRedirect(int? status) =>
      status != null && status >= 300 && status < 400;

  static Uri _validateUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw SubscriptionException('Not a valid URL');
    }
    if (uri.scheme != 'https') {
      throw SubscriptionException(
        'Only https subscriptions are allowed (got ${uri.scheme})',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw SubscriptionException('Credentials in the URL are not allowed');
    }
    return uri;
  }

  /// Rejects hosts that resolve into the device's own networks, which would let
  /// a crafted URL reach loopback services or the local LAN.
  static Future<void> _assertPublicHost(String host) async {
    final List<InternetAddress> addresses;
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      addresses = [literal];
    } else {
      try {
        addresses = await InternetAddress.lookup(host);
      } on SocketException {
        throw SubscriptionException('Cannot resolve $host');
      }
    }

    if (addresses.isEmpty) {
      throw SubscriptionException('Cannot resolve $host');
    }
    for (final address in addresses) {
      if (_isPrivate(address)) {
        throw SubscriptionException(
          '$host resolves to a non-public address (${address.address})',
        );
      }
    }
  }

  static bool _isPrivate(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return switch (bytes[0]) {
        0 || 10 || 127 => true,
        100 => bytes[1] >= 64 && bytes[1] <= 127, // CGNAT 100.64/10
        169 => bytes[1] == 254,
        172 => bytes[1] >= 16 && bytes[1] <= 31,
        192 => (bytes[1] == 168) || (bytes[1] == 0 && bytes[2] == 0),
        198 => bytes[1] == 18 || bytes[1] == 19, // benchmarking + fake-ip range
        _ => bytes[0] >= 224,
      };
    }
    if (bytes.every((b) => b == 0)) return true;
    if (bytes[0] == 0xfc || bytes[0] == 0xfd) return true; // fc00::/7
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true; // fe80::/10
    // IPv4-mapped ::ffff:0:0/96 must be judged by its embedded IPv4 address.
    final mapped =
        bytes.sublist(0, 10).every((b) => b == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (mapped) {
      return _isPrivate(
        InternetAddress.fromRawAddress(Uint8List.fromList(bytes.sublist(12))),
      );
    }
    return false;
  }

  static String? _filename(String? contentDisposition) {
    if (contentDisposition == null) return null;
    final match = RegExp(
      r'filename\*?=(?:UTF-8'
      r"''"
      r'|")?([^";]+)',
      caseSensitive: false,
    ).firstMatch(contentDisposition);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final decoded = Uri.decodeComponent(raw);
    return decoded.replaceAll(RegExp(r'\.(ya?ml|txt|conf)$'), '');
  }
}
