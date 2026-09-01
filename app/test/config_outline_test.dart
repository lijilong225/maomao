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
    // `use:` members live in a provider file only the running core downloads.
    expect(outline.groups.last.all, isEmpty);
  });

  test('returns nothing for configs without groups or invalid yaml', () {
    expect(parseConfigOutline('proxies: []').groups, isEmpty);
    expect(parseConfigOutline('\tnot: yaml').groups, isEmpty);
  });
}
