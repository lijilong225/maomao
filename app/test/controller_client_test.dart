import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maomao/src/api/controller_client.dart';
import 'package:maomao/src/core/core_models.dart';

/// Body shaped like the controller's `/proxies` answer.
final _proxiesBody = jsonEncode({
  'proxies': {
    'GLOBAL': {
      'type': 'Fallback',
      'name': 'GLOBAL',
      'udp': true,
      'history': <dynamic>[],
      'all': ['select', 'direct'],
      'now': 'select',
    },
    'select': {
      'type': 'Selector',
      'name': 'select',
      'udp': true,
      'history': <dynamic>[],
      'all': ['direct'],
      'now': 'direct',
    },
  },
});

/// Starts a controller stand-in and returns a client aimed at it.
///
/// [contentType] is what the server puts on `/proxies`, which is the whole point
/// of these tests: the two cores label that response differently.
Future<ControllerClient> _serveProxies(
  ContentType? contentType, {
  String body = '',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);

  server.listen((request) async {
    final response = request.response;
    if (request.uri.path == '/proxies') {
      if (contentType == null) {
        response.headers.removeAll(HttpHeaders.contentTypeHeader);
      } else {
        response.headers.contentType = contentType;
      }
      response.write(body.isEmpty ? _proxiesBody : body);
    } else if (request.uri.path == '/providers/proxies') {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'providers': <String, dynamic>{}}));
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  });

  final client = ControllerClient(
    ControllerInfo(addr: '127.0.0.1:${server.port}', secret: 'secret'),
  );
  addTearDown(client.close);
  return client;
}

void main() {
  // sing-box writes /proxies to the socket itself instead of going through its
  // JSON renderer, so the body arrives labelled text/plain by Go's sniffer.
  test('reads proxies the controller failed to label as JSON', () async {
    final client = await _serveProxies(ContentType.text);

    final nodes = await client.proxies();

    expect(nodes.keys, containsAll(['GLOBAL', 'select']));
    expect(nodes['select']!.type, 'Selector');
    expect(nodes['select']!.now, 'direct');
    expect(nodes['select']!.isSelectable, isTrue);
  });

  test('reads proxies when no content type is sent at all', () async {
    final client = await _serveProxies(null);

    final nodes = await client.proxies();

    expect(nodes.keys, containsAll(['GLOBAL', 'select']));
  });

  // mihomo labels everything, and the merged snapshot is what the proxies page
  // actually asks for.
  test('merges a snapshot from a properly labelled controller', () async {
    final client = await _serveProxies(ContentType.json);

    final snapshot = await client.snapshot();

    expect(snapshot.nodes.keys, containsAll(['GLOBAL', 'select']));
    expect(snapshot.groups.map((group) => group.name), contains('select'));
  });

  // Bodies that are not JSON must stay as they are: guessing would turn a
  // readable server message into a parse failure.
  test('leaves a non-JSON body alone', () async {
    final client = await _serveProxies(ContentType.text, body: 'not json');

    await expectLater(client.proxies(), throwsA(isA<ControllerException>()));
  });

  // sing-box answers 400 "Must be a Selector" for anything else, including the
  // GLOBAL group it injects for clash dashboards.
  test('only offers a switch a sing-box controller would accept', () async {
    final client = await _serveProxies(ContentType.json);
    final nodes = await client.proxies();

    expect(
      nodes['select']!.switchable(automaticGroupsSwitchable: false),
      isTrue,
    );
    expect(
      nodes['GLOBAL']!.switchable(automaticGroupsSwitchable: false),
      isFalse,
    );
    expect(
      nodes['GLOBAL']!.switchable(automaticGroupsSwitchable: true),
      isTrue,
    );
    expect(CoreEngine.singbox.switchesAutomaticGroups, isFalse);
    expect(CoreEngine.mihomo.switchesAutomaticGroups, isTrue);
  });
}
