import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/profile/selection_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps a selection per profile', () async {
    const store = ProxySelectionStore();
    await store.save('a', {'Proxy': 'node-a'});
    await store.save('b', {'Proxy': 'node-b'});

    expect(await store.load('a'), {'Proxy': 'node-a'});
    expect(await store.load('b'), {'Proxy': 'node-b'});
  });

  test('reports nothing for an unknown or missing profile', () async {
    const store = ProxySelectionStore();
    expect(await store.load('never-saved'), isEmpty);
    expect(await store.load(null), isEmpty);
  });

  test('ignores a stored value that is not a group map', () async {
    SharedPreferences.setMockInitialValues({'proxy_selection_a': '"broken"'});
    expect(await const ProxySelectionStore().load('a'), isEmpty);
  });
}
