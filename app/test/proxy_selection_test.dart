import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/core/core_models.dart';
import 'package:maomao/src/profile/selection_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps a selection per profile', () async {
    const store = ProxySelectionStore();
    await store.save('a', CoreEngine.mihomo, {'Proxy': 'node-a'});
    await store.save('b', CoreEngine.mihomo, {'Proxy': 'node-b'});

    expect(await store.load('a', CoreEngine.mihomo), {'Proxy': 'node-a'});
    expect(await store.load('b', CoreEngine.mihomo), {'Proxy': 'node-b'});
  });

  test('keeps a selection per engine', () async {
    const store = ProxySelectionStore();
    await store.save('a', CoreEngine.mihomo, {'Proxy': 'node-a'});
    await store.save('a', CoreEngine.singbox, {'select': 'node-b'});

    expect(await store.load('a', CoreEngine.mihomo), {'Proxy': 'node-a'});
    expect(await store.load('a', CoreEngine.singbox), {'select': 'node-b'});
  });

  test('reports nothing for an unknown or missing profile', () async {
    const store = ProxySelectionStore();
    expect(await store.load('never-saved', CoreEngine.mihomo), isEmpty);
    expect(await store.load(null, CoreEngine.mihomo), isEmpty);
  });

  test('ignores a stored value that is not a group map', () async {
    SharedPreferences.setMockInitialValues({'proxy_selection_a': '"broken"'});
    expect(
      await const ProxySelectionStore().load('a', CoreEngine.mihomo),
      isEmpty,
    );
  });

  test('reads selections saved before the engine setting existed', () async {
    SharedPreferences.setMockInitialValues({
      'proxy_selection_a': '{"Proxy":"node-a"}',
    });
    expect(await const ProxySelectionStore().load('a', CoreEngine.mihomo), {
      'Proxy': 'node-a',
    });
  });
}
