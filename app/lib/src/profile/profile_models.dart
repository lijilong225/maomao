import 'dart:convert';

/// Quota reported by a subscription's `subscription-userinfo` response header.
class SubscriptionUserInfo {
  const SubscriptionUserInfo({
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire,
  });

  final int upload;
  final int download;
  final int total;
  final DateTime? expire;

  int get used => upload + download;

  bool get hasQuota => total > 0;

  double get usedRatio => hasQuota ? (used / total).clamp(0.0, 1.0) : 0.0;

  /// Parses `upload=1234; download=5678; total=9999; expire=1700000000`.
  static SubscriptionUserInfo? parseHeader(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final fields = <String, int>{};
    for (final part in raw.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final key = part.substring(0, index).trim().toLowerCase();
      final value = int.tryParse(part.substring(index + 1).trim());
      if (value != null) fields[key] = value;
    }
    if (fields.isEmpty) return null;

    final expire = fields['expire'];
    return SubscriptionUserInfo(
      upload: fields['upload'] ?? 0,
      download: fields['download'] ?? 0,
      total: fields['total'] ?? 0,
      expire: expire != null && expire > 0
          ? DateTime.fromMillisecondsSinceEpoch(expire * 1000)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire?.millisecondsSinceEpoch,
  };

  static SubscriptionUserInfo fromJson(Map<String, dynamic> json) {
    final expire = json['expire'] as int?;
    return SubscriptionUserInfo(
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      expire: expire != null
          ? DateTime.fromMillisecondsSinceEpoch(expire)
          : null,
    );
  }
}

enum ProfileSource { remote, local }

/// A subscription or local config, plus the user's declarative override.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.source,
    this.url,
    this.overrideYaml = '',
    this.autoUpdateInterval,
    this.updatedAt,
    this.userInfo,
  });

  final String id;
  final String name;
  final ProfileSource source;

  /// Remote subscription URL. Sensitive: kept out of plain preferences.
  final String? url;

  /// Declarative YAML patch merged onto the subscription body.
  final String overrideYaml;
  final Duration? autoUpdateInterval;
  final DateTime? updatedAt;
  final SubscriptionUserInfo? userInfo;

  bool get isRemote => source == ProfileSource.remote;

  bool get needsUpdate {
    final interval = autoUpdateInterval;
    final last = updatedAt;
    if (!isRemote || interval == null) return false;
    if (last == null) return true;
    return DateTime.now().difference(last) >= interval;
  }

  Profile copyWith({
    String? name,
    String? url,
    String? overrideYaml,
    Duration? autoUpdateInterval,
    bool clearAutoUpdate = false,
    DateTime? updatedAt,
    SubscriptionUserInfo? userInfo,
    bool clearUserInfo = false,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    source: source,
    url: url ?? this.url,
    overrideYaml: overrideYaml ?? this.overrideYaml,
    autoUpdateInterval: clearAutoUpdate
        ? null
        : (autoUpdateInterval ?? this.autoUpdateInterval),
    updatedAt: updatedAt ?? this.updatedAt,
    userInfo: clearUserInfo ? null : (userInfo ?? this.userInfo),
  );

  /// [includeUrl] is false for the plain-preferences copy; the URL is stored
  /// separately in encrypted storage.
  Map<String, dynamic> toJson({bool includeUrl = true}) => {
    'id': id,
    'name': name,
    'source': source.name,
    if (includeUrl && url != null) 'url': url,
    'overrideYaml': overrideYaml,
    'autoUpdateMinutes': autoUpdateInterval?.inMinutes,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
    'userInfo': userInfo?.toJson(),
  };

  static Profile fromJson(Map<String, dynamic> json) {
    final minutes = json['autoUpdateMinutes'] as int?;
    final updatedAt = json['updatedAt'] as int?;
    final userInfo = json['userInfo'] as Map<String, dynamic>?;
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'unnamed',
      source: json['source'] == 'local'
          ? ProfileSource.local
          : ProfileSource.remote,
      url: json['url'] as String?,
      overrideYaml: json['overrideYaml'] as String? ?? '',
      autoUpdateInterval: minutes != null && minutes > 0
          ? Duration(minutes: minutes)
          : null,
      updatedAt: updatedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedAt)
          : null,
      userInfo: userInfo != null
          ? SubscriptionUserInfo.fromJson(userInfo)
          : null,
    );
  }

  @override
  String toString() => jsonEncode(toJson(includeUrl: false));
}
