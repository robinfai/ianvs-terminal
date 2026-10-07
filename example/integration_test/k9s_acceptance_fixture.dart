import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Synthetic Kubernetes discovery/list/watch endpoints and deterministic AI
/// responses. Every request stays on loopback; no user kubeconfig is used.
class K9sAcceptanceFixture {
  K9sAcceptanceFixture._(this.server);
  final HttpServer server;
  final requests = <Map<String, Object?>>[];
  final aiPayloads = <Object?>[];
  final _closed = Completer<void>();
  Map<String, Object?>? nextProposal;
  static const _resources = {
    'pods': 'Pod',
    'namespaces': 'Namespace',
    'nodes': 'Node',
    'events': 'Event',
  };
  static const Map<String, Object?> _pod = {
    'apiVersion': 'v1',
    'kind': 'Pod',
    'metadata': {
      'name': 'trail-fixture-pod',
      'namespace': 'default',
      'uid': 'fixture-pod',
      'resourceVersion': '1',
      'creationTimestamp': '2026-10-01T00:00:00Z',
    },
    'spec': {
      'nodeName': 'fixture-node',
      'containers': [
        {'name': 'fixture', 'image': 'fixture-only:1'},
      ],
    },
    'status': {
      'phase': 'Running',
      'podIP': '127.0.0.2',
      'containerStatuses': [
        {
          'name': 'fixture',
          'ready': true,
          'restartCount': 0,
          'image': 'fixture-only:1',
          'imageID': 'fixture-only',
          'state': {
            'running': {'startedAt': '2026-10-01T00:00:00Z'},
          },
        },
      ],
    },
  };

  static Future<K9sAcceptanceFixture> start() async {
    final fixture = K9sAcceptanceFixture._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) => unawaited(fixture._handle(request)));
    return fixture;
  }

  Future<void> writeConfig(Directory home) async {
    await File('${home.path}/kubeconfig.json').writeAsString(
      jsonEncode({
        'apiVersion': 'v1',
        'kind': 'Config',
        'current-context': 'trail-fixture',
        'clusters': [
          {
            'name': 'trail-fixture',
            'cluster': {'server': 'http://127.0.0.1:${server.port}'},
          },
        ],
        'users': [
          {'name': 'fixture', 'user': <String, Object?>{}},
        ],
        'contexts': [
          {
            'name': 'trail-fixture',
            'context': {
              'cluster': 'trail-fixture',
              'user': 'fixture',
              'namespace': 'default',
            },
          },
        ],
      }),
    );
    await Directory('${home.path}/k9s').create();
    await File('${home.path}/k9s/config.yaml').writeAsString(
      'k9s:\n  skipLatestRevCheck: true\n  readOnly: true\n'
      '  ui:\n    enableMouse: true\n',
    );
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add({'method': request.method, 'path': request.uri.toString()});
    try {
      final path = request.uri.path;
      Object? data;
      if (path == '/v1/chat/completions' && request.method == 'POST') {
        aiPayloads.add(jsonDecode(await utf8.decoder.bind(request).join()));
        data = {
          'id': 'k9s-fixture-${aiPayloads.length}',
          'model': 'fixture',
          'choices': [
            {
              'message':
                  nextProposal ??
                  {
                    'role': 'assistant',
                    'content': 'The approved input was submitted.',
                  },
            },
          ],
        };
        nextProposal = null;
      } else if (request.method == 'POST' &&
          path == '/apis/authorization.k8s.io/v1/selfsubjectaccessreviews') {
        // Kubernetes clients may use protobuf bodies for this read-only check.
        await request.drain<void>();
        request.response.statusCode = HttpStatus.created;
        data = {
          'apiVersion': 'authorization.k8s.io/v1',
          'kind': 'SelfSubjectAccessReview',
          'status': {'allowed': true},
        };
      } else if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else if (path == '/version') {
        data = {
          'major': '1',
          'minor': '32',
          'gitVersion': 'v1.32.0',
          'gitCommit': 'fixture',
          'platform': 'darwin/arm64',
        };
      } else if (path == '/api') {
        data = {
          'apiVersion': 'v1',
          'kind': 'APIVersions',
          'versions': ['v1'],
        };
      } else if (path == '/apis') {
        data = {
          'apiVersion': 'v1',
          'kind': 'APIGroupList',
          'groups': <Object?>[],
        };
      } else if (path == '/api/v1') {
        data = {
          'apiVersion': 'v1',
          'kind': 'APIResourceList',
          'groupVersion': 'v1',
          'resources': [
            for (final resource in _resources.entries)
              {
                'name': resource.key,
                'singularName': resource.value.toLowerCase(),
                'namespaced': ['pods', 'events'].contains(resource.key),
                'kind': resource.value,
                'verbs': ['get', 'list', 'watch'],
                'shortNames': resource.key == 'pods' ? ['po'] : <String>[],
              },
          ],
        };
      } else if (_resources.containsKey(request.uri.pathSegments.last)) {
        final resource = request.uri.pathSegments.last;
        final items = <Object?>[
          if (resource == 'pods') _pod,
          if (resource == 'namespaces')
            {
              'apiVersion': 'v1',
              'kind': 'Namespace',
              'metadata': {
                'name': 'default',
                'uid': 'fixture-namespace',
                'resourceVersion': '1',
              },
              'status': {'phase': 'Active'},
            },
        ];
        if (request.uri.queryParameters['watch'] == 'true') {
          request.response.headers.contentType = ContentType.json;
          for (final item in items) {
            request.response.writeln(
              jsonEncode({'type': 'ADDED', 'object': item}),
            );
          }
          await request.response.flush();
          await _closed.future;
          await request.response.close();
          return;
        }
        data = {
          'apiVersion': 'v1',
          'kind': '${_resources[resource]}List',
          'metadata': {'resourceVersion': '1'},
          'items': items,
        };
      } else if (path.endsWith('/customresourcedefinitions')) {
        data = {
          'apiVersion': 'apiextensions.k8s.io/v1',
          'kind': 'CustomResourceDefinitionList',
          'metadata': {'resourceVersion': '1'},
          'items': <Object?>[],
        };
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      request.response.headers.contentType = ContentType.json;
      if (data != null) request.response.write(jsonEncode(data));
      await request.response.close();
    } on HttpException {
      // A watch is cancelled when k9s exits or switches views.
    } on SocketException {
      // The fixture also shuts down pending watch connections during teardown.
    }
  }

  void proposeExit() {
    nextProposal = {
      'role': 'assistant',
      'content': 'Review the keys to exit this isolated k9s session.',
      'tool_calls': [
        {
          'id': 'k9s-exit-${aiPayloads.length + 1}',
          'type': 'function',
          'function': {
            'name': 'send_keys',
            'arguments': jsonEncode({
              'keys': [
                {'key': 'ESC'},
                {'text': ':q'},
                {'key': 'ENTER'},
              ],
              'reason': 'Exit the read-only synthetic cluster view',
            }),
          },
        },
      ],
    };
  }

  Future<void> close() async {
    if (!_closed.isCompleted) _closed.complete();
    await server.close(force: true);
  }
}
