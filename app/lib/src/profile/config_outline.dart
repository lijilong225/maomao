import 'package:yaml/yaml.dart';

import '../api/controller_models.dart';

/// Group type as spelled in a config file mapped to the name the controller
/// reports, so both data sources render identically.
const _groupTypes = {
  'select': 'Selector',
  'url-test': 'URLTest',
  'fallback': 'Fallback',
  'load-balance': 'LoadBalance',
  'relay': 'Relay',
};

/// Reads policy groups straight out of a config file so they can be browsed
/// before the tunnel is up.
///
/// Members pulled in through `use:` live in remote provider files that only the
/// running core downloads, so such a group comes back with no members.
ProxySnapshot parseConfigOutline(String yaml) {
  final Object? doc;
  try {
    doc = loadYaml(yaml);
  } catch (_) {
    return ProxySnapshot.empty;
  }
  if (doc is! Map) return ProxySnapshot.empty;

  final rawGroups = doc['proxy-groups'];
  if (rawGroups is! List) return ProxySnapshot.empty;

  final groups = <ProxyNode>[];
  for (final entry in rawGroups) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String || name.isEmpty) continue;

    final raw = entry['proxies'];
    final members = [
      if (raw is List)
        for (final member in raw)
          if (member is String) member,
    ];
    final type = entry['type'];

    groups.add(
      ProxyNode(
        name: name,
        type: _groupTypes[type] ?? (type is String ? type : 'Unknown'),
        udp: false,
        history: const [],
        now: members.isEmpty ? null : members.first,
        all: members,
      ),
    );
  }

  return ProxySnapshot(
    nodes: {for (final group in groups) group.name: group},
    groups: groups,
  );
}
