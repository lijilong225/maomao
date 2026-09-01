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

  /// Group types the core lets the user switch directly. These are exactly the
  /// ones implementing `outboundgroup.SelectAble`; picking a member of an
  /// automatic group pins it until the next reload.
  static const selectableTypes = {'Selector', 'URLTest', 'Fallback'};

  bool get isSelectable => selectableTypes.contains(type);

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

/// Provider name the core reserves for everything declared inline in the
/// config file. Its node list follows the config file order.
const reservedProviderName = 'default';

/// Merged view of `/proxies` and `/providers/proxies`.
///
/// `/proxies` is a Go map, so its JSON keys arrive sorted alphabetically and the
/// config file order is lost. Nodes pulled from `proxy-providers` are missing
/// from it altogether, which also hides their latency history.
class ProxySnapshot {
  const ProxySnapshot({required this.nodes, required this.groups});

  static const empty = ProxySnapshot(nodes: {}, groups: []);

  /// Every known node, including provider-backed ones.
  final Map<String, ProxyNode> nodes;

  /// Groups in config file order.
  final List<ProxyNode> groups;

  static ProxySnapshot merge({
    required Map<String, ProxyNode> proxies,
    required Map<String, List<ProxyNode>> providers,
  }) {
    final nodes = <String, ProxyNode>{};
    for (final members in providers.values) {
      for (final node in members) {
        nodes[node.name] = node;
      }
    }
    // `/proxies` wins on conflicts: it is the authoritative view of groups.
    nodes.addAll(proxies);

    final ranks = <String, int>{};
    for (final node in providers[reservedProviderName] ?? const <ProxyNode>[]) {
      ranks.putIfAbsent(node.name, () => ranks.length);
    }
    // Anything the reserved provider does not list (such as an implicit GLOBAL)
    // goes last, ordered by name so the result stays deterministic.
    int rankOf(ProxyNode node) => ranks[node.name] ?? ranks.length;

    final groups = nodes.values.where((node) => node.isGroup).toList()
      ..sort((a, b) {
        final byConfig = rankOf(a).compareTo(rankOf(b));
        return byConfig != 0 ? byConfig : a.name.compareTo(b.name);
      });

    return ProxySnapshot(nodes: nodes, groups: groups);
  }
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

/// Vehicle types whose content is fetched, so the core can refresh them.
///
/// `Compatible` wraps proxies written straight into the config file and
/// `Inline` wraps a payload, neither of which has anything to re-download.
const _fetchedVehicles = {'HTTP', 'File'};

/// A `proxy-providers` entry as reported by `/providers/proxies`.
class ProxyProviderInfo {
  const ProxyProviderInfo({
    required this.name,
    required this.vehicleType,
    required this.proxyCount,
    this.updatedAt,
  });

  final String name;
  final String vehicleType;
  final int proxyCount;
  final DateTime? updatedAt;

  bool get isUpdatable => _fetchedVehicles.contains(vehicleType);

  static ProxyProviderInfo fromJson(String name, Map<String, dynamic> json) =>
      ProxyProviderInfo(
        name: json['name'] as String? ?? name,
        vehicleType: json['vehicleType'] as String? ?? 'Unknown',
        proxyCount: (json['proxies'] as List<dynamic>? ?? const []).length,
        updatedAt: _parseTime(json['updatedAt']),
      );
}

/// A `rule-providers` entry as reported by `/providers/rules`.
class RuleProviderInfo {
  const RuleProviderInfo({
    required this.name,
    required this.behavior,
    required this.format,
    required this.vehicleType,
    required this.ruleCount,
    this.updatedAt,
  });

  final String name;
  final String behavior;
  final String format;
  final String vehicleType;
  final int ruleCount;
  final DateTime? updatedAt;

  bool get isUpdatable => _fetchedVehicles.contains(vehicleType);

  static RuleProviderInfo fromJson(String name, Map<String, dynamic> json) =>
      RuleProviderInfo(
        name: json['name'] as String? ?? name,
        behavior: json['behavior'] as String? ?? '',
        format: json['format'] as String? ?? '',
        vehicleType: json['vehicleType'] as String? ?? 'Unknown',
        ruleCount: (json['ruleCount'] as num?)?.toInt() ?? 0,
        updatedAt: _parseTime(json['updatedAt']),
      );
}

/// Go marshals a never-set `time.Time` as year 1, which must not be shown as an
/// update that happened two millennia ago.
DateTime? _parseTime(Object? raw) {
  if (raw is! String) return null;
  final time = DateTime.tryParse(raw);
  if (time == null || time.year < 2000) return null;
  return time;
}
