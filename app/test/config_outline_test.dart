import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/profile/config_outline.dart';

void main() {
  test('keeps proxy-groups in config file order', () {
    final outline = parseConfigOutline('''
proxies:
  - name: node-a
    type: ss
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node-a, DIRECT]
  - name: Auto
    type: url-test
    use: [remote]
''');

    expect(outline.groups.map((g) => g.name), ['Proxy', 'Auto']);
    expect(outline.groups.first.type, 'Selector');
    expect(outline.groups.first.all, ['node-a', 'DIRECT']);
    // No cached body for `remote`, so the group stays empty.
    expect(outline.groups.last.all, isEmpty);
  });

  test('expands use: from cached provider bodies', () {
    const config = '''
proxy-providers:
  remote:
    type: http
    url: https://example.com/sub
proxy-groups:
  - name: Auto
    type: url-test
    use: [remote]
''';

    expect(
      parseConfigProviders(config).map((p) => p.url),
      ['https://example.com/sub'],
    );

    final outline = parseConfigOutline(
      config,
      providerBodies: {
        'remote': '''
proxies:
  - name: hk-01
    type: ss
  - name: jp-01
    type: vmess
''',
      },
    );

    expect(outline.groups.single.all, ['hk-01', 'jp-01']);
    expect(outline.nodes['hk-01']?.type, 'ss');
  });

  test('applies filters to provider members', () {
    final outline = parseConfigOutline(
      '''
proxy-providers:
  remote:
    type: http
    url: https://example.com/sub
    exclude-type: vmess
proxy-groups:
  - name: HK
    type: select
    use: [remote]
    filter: "HK"
    exclude-filter: "expire"
''',
      providerBodies: {
        'remote': '''
proxies:
  - name: HK-01
    type: ss
  - name: HK-expire
    type: ss
  - name: HK-02
    type: vmess
  - name: JP-01
    type: ss
''',
      },
    );

    expect(outline.groups.single.all, ['HK-01']);
  });

  test('expands inline providers and include-all', () {
    final outline = parseConfigOutline('''
proxies:
  - name: node-b
    type: ss
  - name: node-a
    type: ss
proxy-providers:
  local:
    type: inline
    payload:
      - name: inline-01
        type: trojan
proxy-groups:
  - name: All
    type: select
    include-all: true
''');

    // The core sorts inline nodes before appending providers.
    expect(outline.groups.single.all, ['node-a', 'node-b', 'inline-01']);
  });

  test('returns nothing for configs without groups or invalid yaml', () {
    expect(parseConfigOutline('proxies: []').groups, isEmpty);
    expect(parseConfigOutline('\tnot: yaml').groups, isEmpty);
  });
}
