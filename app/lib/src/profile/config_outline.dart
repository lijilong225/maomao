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

/// Rule set `behavior` / `format` as spelled in a config file mapped to the
/// name the controller reports.
const _behaviors = {
  'domain': 'Domain',
  'ipcidr': 'IPCIDR',
  'classical': 'Classical',
};
const _formats = {
  '': 'YamlRule',
  'yaml': 'YamlRule',
  'text': 'TextRule',
  'mrs': 'MrsRule',
};

/// Config sections that declare provider collections.
enum ProviderSection {
  proxies('proxy-providers', 'proxies'),
  rules('rule-providers', 'rules');

  const ProviderSection(this.key, this.cachePrefix);

  /// Top level key holding the section.
  final String key;

  /// Sub-directory of the core home where a downloaded body is cached.
  final String cachePrefix;
}

/// A `proxy-providers` or `rule-providers` entry as declared in a config file.
class ConfigProviderRef {
  const ConfigProviderRef({
    required this.section,
    required this.name,
    required this.type,
    this.url,
    this.path,
    this.behavior = '',
    this.format = '',
    this.payloadCount = 0,
  });

  final ProviderSection section;
  final String name;

  /// `http`, `file` or `inline`.
  final String type;
  final String? url;
  final String? path;

  /// `rule-providers` only.
  final String behavior;

  /// `rule-providers` only; an omitted format means yaml.
  final String format;

  /// Entries of an `inline` payload, which lives in the config file itself.
  final int payloadCount;

  /// Whether the core downloads the content, which is what an update refreshes
  /// and what leaves a cache file behind.
  bool get isFetched => type == 'http' || type == 'file';

  /// Whether the app itself can refresh the body while the core is down, which
  /// needs a URL to fetch. A `file` provider is supplied by the user and an
  /// `inline` one lives in the config file, so neither is downloadable.
  ///
  /// A `path` that escapes the core home is refused too: a config file is
  /// untrusted input, and the app must only ever write inside its own sandbox.
  bool get isDownloadable {
    if (type != 'http' || (url?.isEmpty ?? true)) return false;
    final target = path;
    if (target == null || target.isEmpty) return true;
    return !target.startsWith('/') &&
        !target.split(RegExp(r'[/\\]')).contains('..');
  }

  /// Behaviour as the controller reports it, so an offline row reads like a
  /// live one.
  String get behaviorLabel => _behaviors[behavior] ?? behavior;

  /// Format as the controller reports it.
  String get formatLabel => _formats[format] ?? format;
}

/// Every entry declared under [section], `inline` ones included.
List<ConfigProviderRef> parseConfigProviderRefs(
  String yaml,
  ProviderSection section,
) {
  final raw = _loadMap(yaml)?[section.key];
  if (raw is! Map) return const [];

  final refs = <ConfigProviderRef>[];
  raw.forEach((key, value) {
    if (key is! String || value is! Map) return;
    final type = value['type'];
    if (type is! String) return;
    final payload = value['payload'];
    refs.add(
      ConfigProviderRef(
        section: section,
        name: key,
        type: type,
        url: value['url'] is String ? value['url'] as String : null,
        path: value['path'] is String ? value['path'] as String : null,
        behavior: value['behavior'] is String
            ? value['behavior'] as String
            : '',
        format: value['format'] is String ? value['format'] as String : '',
        payloadCount: payload is List ? payload.length : 0,
      ),
    );
  });
  return refs;
}

/// Providers that must be read from disk before [parseConfigOutline] can list
/// their members. The core caches an `http` provider under
/// `<home>/proxies/<md5 of url>` and reads a `file` provider from its `path`,
/// resolved against the core home directory when relative.
List<ConfigProviderRef> parseConfigProviders(String yaml) => [
  for (final ref in parseConfigProviderRefs(yaml, ProviderSection.proxies))
    if (ref.isFetched) ref,
];

/// Nodes in a `proxy-providers` body the core downloaded.
int countProviderProxies(String body) =>
    _parseNodes(_loadMap(body)?['proxies']).length;

/// Rules in a `rule-providers` body the core downloaded, or null for a binary
/// bundle whose entries cannot be counted without decoding it.
int? countProviderRules(String body, String format) {
  switch (format) {
    case 'mrs':
      return null;
    case 'text':
      // The core skips blank lines and `#` / `//` comments.
      return body
          .split('\n')
          .map((line) => line.trim())
          .where(
            (line) =>
                line.isNotEmpty &&
                !line.startsWith('#') &&
                !line.startsWith('//'),
          )
          .length;
    default:
      final payload = _loadMap(body)?['payload'];
      return payload is List ? payload.length : 0;
  }
}

/// Reads policy groups straight out of a config file so they can be browsed
/// before the tunnel is up.
///
/// [providerBodies] maps a `proxy-providers` name to the raw body of its node
/// list, as fetched by the core on an earlier run. Providers missing from the
/// map simply contribute no members, which is what a never-updated
/// subscription looks like.
ProxySnapshot parseConfigOutline(
  String yaml, {
  Map<String, String> providerBodies = const {},
}) {
  final doc = _loadMap(yaml);
  if (doc == null) return ProxySnapshot.empty;

  final inline = _parseNodes(doc['proxies']);
  final providers = _parseProviders(doc['proxy-providers'], providerBodies);

  final rawGroups = doc['proxy-groups'];
  if (rawGroups is! List) return ProxySnapshot.empty;

  // The core sorts both lists before expanding `include-all*`.
  final allProxies = inline.map((node) => node.name).toList()..sort();
  final allProviders = providers.keys.toList()..sort();

  final groups = <ProxyNode>[];
  for (final entry in rawGroups) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String || name.isEmpty) continue;

    groups.add(
      _buildGroup(
        entry: entry,
        name: name,
        inline: inline,
        providers: providers,
        allProxies: allProxies,
        allProviders: allProviders,
      ),
    );
  }

  final nodes = <String, ProxyNode>{
    for (final node in inline) node.name: _leaf(node),
    for (final members in providers.values)
      for (final node in members) node.name: _leaf(node),
    for (final group in groups) group.name: group,
  };

  return ProxySnapshot(nodes: nodes, groups: groups);
}

ProxyNode _buildGroup({
  required Map entry,
  required String name,
  required List<_Node> inline,
  required Map<String, List<_Node>> providers,
  required List<String> allProxies,
  required List<String> allProviders,
}) {
  final filter = _Filter.from(entry);

  var includeAllProxies = entry['include-all-proxies'] == true;
  var includeAllProviders = entry['include-all-providers'] == true;
  if (entry['include-all'] == true) {
    includeAllProxies = true;
    includeAllProviders = true;
  }

  // Explicit `proxies:` entries bypass the group filter, matching the
  // "compatible provider unneeded filter" branch in the core.
  final members = <String>[..._names(entry['proxies'])];
  if (includeAllProxies) {
    members.addAll(
      filter.hasInclude
          ? filter.include(inline).map((node) => node.name)
          : allProxies,
    );
  }

  final used = [
    if (includeAllProviders) ...allProviders else ..._names(entry['use']),
  ];
  for (final providerName in used) {
    final nodes = providers[providerName];
    if (nodes == null) continue;
    for (final node in filter.apply(nodes)) {
      members.add(node.name);
    }
  }

  final unique = <String>[];
  final seen = <String>{};
  for (final member in members) {
    if (seen.add(member)) unique.add(member);
  }

  final type = entry['type'];
  return ProxyNode(
    name: name,
    type: _groupTypes[type] ?? (type is String ? type : 'Unknown'),
    udp: false,
    history: const [],
    // The core defaults a group to its first member until a health check or an
    // explicit selection moves it.
    now: unique.isEmpty ? null : unique.first,
    all: unique,
  );
}

Map<String, dynamic>? _loadMap(String yaml) {
  final Object? doc;
  try {
    doc = loadYaml(yaml);
  } catch (_) {
    return null;
  }
  if (doc is! Map) return null;
  return {for (final entry in doc.entries) '${entry.key}': entry.value};
}

/// Node lists keyed by provider name, with each provider's own filters applied.
Map<String, List<_Node>> _parseProviders(
  Object? raw,
  Map<String, String> bodies,
) {
  if (raw is! Map) return const {};

  final result = <String, List<_Node>>{};
  raw.forEach((key, value) {
    if (key is! String || value is! Map) return;
    final filter = _Filter.from(value);

    if (value['type'] == 'inline') {
      result[key] = filter.apply(_parseNodes(value['payload']));
      return;
    }

    final body = bodies[key];
    if (body == null) {
      result[key] = const [];
      return;
    }
    final doc = _loadMap(body);
    result[key] = filter.apply(_parseNodes(doc?['proxies']));
  });
  return result;
}

List<_Node> _parseNodes(Object? raw) {
  if (raw is! List) return const [];
  final nodes = <_Node>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String || name.isEmpty) continue;
    final type = entry['type'];
    nodes.add(_Node(name, type is String ? type : ''));
  }
  return nodes;
}

List<String> _names(Object? raw) => [
  if (raw is List)
    for (final entry in raw)
      if (entry is String) entry,
];

ProxyNode _leaf(_Node node) => ProxyNode(
  name: node.name,
  type: node.type.isEmpty ? 'Unknown' : node.type,
  udp: false,
  history: const [],
);

class _Node {
  const _Node(this.name, this.type);

  final String name;
  final String type;
}

/// The `filter` / `exclude-filter` / `exclude-type` trio shared by groups and
/// providers.
///
/// The core compiles these with `regexp2`, which accepts constructs Dart's
/// [RegExp] rejects; an unparsable pattern is dropped rather than failing the
/// whole preview, so an offline member list can differ from the running one.
class _Filter {
  _Filter._(this._include, this._exclude, this._excludeTypes);

  factory _Filter.from(Map entry) => _Filter._(
    _compile(entry['filter']),
    _compile(entry['exclude-filter']),
    entry['exclude-type'] is String
        ? (entry['exclude-type'] as String)
              .split('|')
              .map((type) => type.toLowerCase())
              .toList()
        : const <String>[],
  );

  final List<RegExp> _include;
  final List<RegExp> _exclude;
  final List<String> _excludeTypes;

  bool get hasInclude => _include.isNotEmpty;

  static List<RegExp> _compile(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    final patterns = <RegExp>[];
    for (final pattern in raw.split('`')) {
      try {
        patterns.add(RegExp(pattern));
      } catch (_) {
        // Unsupported syntax; ignoring it keeps the preview usable.
      }
    }
    return patterns;
  }

  /// Members matching [_include], in the order the patterns appear.
  List<_Node> include(List<_Node> nodes) {
    final picked = <_Node>[];
    final seen = <String>{};
    for (final pattern in _include) {
      for (final node in nodes) {
        if (pattern.hasMatch(node.name) && seen.add(node.name)) {
          picked.add(node);
        }
      }
    }
    return picked;
  }

  List<_Node> apply(List<_Node> nodes) {
    var result = hasInclude ? include(nodes) : nodes;
    if (_exclude.isNotEmpty) {
      result = result
          .where(
            (node) => !_exclude.any((pattern) => pattern.hasMatch(node.name)),
          )
          .toList();
    }
    if (_excludeTypes.isNotEmpty) {
      result = result
          .where((node) => !_excludeTypes.contains(node.type.toLowerCase()))
          .toList();
    }
    return result;
  }
}
