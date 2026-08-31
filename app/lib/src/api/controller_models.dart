/// Data models for the core's RESTful controller responses.
class ProxyDelayHistory {
  const ProxyDelayHistory({required this.time, required this.delay});

  final DateTime? time;
  final int delay;

  static ProxyDelayHistory fromJson(Map<String, dynamic> json) =>
      ProxyDelayHistory(
        time: DateTime.tryParse(json['time'] as String? ?? ''),
        delay: (json['delay'] as num?)?.toInt() ?? 0,
      );
}

class ProxyNode {
  const ProxyNode({
    required this.name,
    required this.type,
    required this.udp,
    required this.history,
    this.now,
    this.all = const [],
    this.alive = true,
  });

  final String name;
  final String type;
  final bool udp;
  final List<ProxyDelayHistory> history;

  /// Currently selected member, only meaningful for groups.
  final String? now;

  /// Member names, only meaningful for groups.
  final List<String> all;
  final bool alive;

  bool get isGroup => all.isNotEmpty;

  /// `Selector` groups are the only ones the user can switch directly.
  bool get isSelectable => type == 'Selector';

  int get latestDelay => history.isEmpty ? 0 : history.last.delay;

  static ProxyNode fromJson(String name, Map<String, dynamic> json) => ProxyNode(
    name: json['name'] as String? ?? name,
    type: json['type'] as String? ?? 'Unknown',
    udp: json['udp'] as bool? ?? false,
    now: json['now'] as String?,
    alive: json['alive'] as bool? ?? true,
    all: (json['all'] as List<dynamic>? ?? const []).cast<String>(),
    history: (json['history'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProxyDelayHistory.fromJson)
        .toList(),
  );
}

class ConnectionMetadata {
  const ConnectionMetadata({
    required this.network,
    required this.type,
    required this.host,
    required this.destinationIP,
    required this.destinationPort,
    required this.sourceIP,
    required this.processPath,
  });

  final String network;
  final String type;
  final String host;
  final String destinationIP;
  final String destinationPort;
  final String sourceIP;
  final String processPath;

  String get target => host.isNotEmpty ? host : destinationIP;

  static ConnectionMetadata fromJson(Map<String, dynamic> json) =>
      ConnectionMetadata(
        network: json['network'] as String? ?? '',
        type: json['type'] as String? ?? '',
        host: json['host'] as String? ?? '',
        destinationIP: json['destinationIP'] as String? ?? '',
        destinationPort: json['destinationPort'] as String? ?? '',
        sourceIP: json['sourceIP'] as String? ?? '',
        processPath: json['processPath'] as String? ?? '',
      );
}

class ConnectionItem {
  const ConnectionItem({
    required this.id,
    required this.metadata,
    required this.upload,
    required this.download,
    required this.start,
    required this.chains,
    required this.rule,
    required this.rulePayload,
  });

  final String id;
  final ConnectionMetadata metadata;
  final int upload;
  final int download;
  final DateTime? start;
  final List<String> chains;
  final String rule;
  final String rulePayload;

  static ConnectionItem fromJson(Map<String, dynamic> json) => ConnectionItem(
    id: json['id'] as String? ?? '',
    metadata: ConnectionMetadata.fromJson(
      (json['metadata'] as Map<String, dynamic>?) ?? const {},
    ),
    upload: (json['upload'] as num?)?.toInt() ?? 0,
    download: (json['download'] as num?)?.toInt() ?? 0,
    start: DateTime.tryParse(json['start'] as String? ?? ''),
    chains: (json['chains'] as List<dynamic>? ?? const []).cast<String>(),
    rule: json['rule'] as String? ?? '',
    rulePayload: json['rulePayload'] as String? ?? '',
  );
}

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.downloadTotal,
    required this.uploadTotal,
    required this.connections,
  });

  const ConnectionSnapshot.empty()
    : downloadTotal = 0,
      uploadTotal = 0,
      connections = const [];

  final int downloadTotal;
  final int uploadTotal;
  final List<ConnectionItem> connections;

  static ConnectionSnapshot fromJson(Map<String, dynamic> json) =>
      ConnectionSnapshot(
        downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
        uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
        connections: (json['connections'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ConnectionItem.fromJson)
            .toList(),
      );
}

class RuleItem {
  const RuleItem({
    required this.type,
    required this.payload,
    required this.proxy,
  });

  final String type;
  final String payload;
  final String proxy;

  static RuleItem fromJson(Map<String, dynamic> json) => RuleItem(
    type: json['type'] as String? ?? '',
    payload: json['payload'] as String? ?? '',
    proxy: json['proxy'] as String? ?? '',
  );
}

class MemoryUsage {
  const MemoryUsage({required this.inuse, required this.oslimit});

  final int inuse;
  final int oslimit;

  static MemoryUsage fromJson(Map<String, dynamic> json) => MemoryUsage(
    inuse: (json['inuse'] as num?)?.toInt() ?? 0,
    oslimit: (json['oslimit'] as num?)?.toInt() ?? 0,
  );
}
