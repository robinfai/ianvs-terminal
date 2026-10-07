// Hermetic process fixture for ACP framing, correlation and capability denial.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  Map<String, Object?>? first;
  Object? permissionRequest;
  final callbacks = <Object?>[];
  void send(Map<String, Object?> value) =>
      stdout.writeln(jsonEncode({'jsonrpc': '2.0', ...value}));
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final input = (jsonDecode(line) as Map).cast<String, Object?>();
    final id = input['id'];
    switch (input['method']) {
      case 'reverse':
        if (first == null) {
          first = input;
        } else {
          send({
            'id': id,
            'result': {'value': (input['params']! as Map)['value']},
          });
          send({
            'id': first['id'],
            'result': {'value': (first['params']! as Map)['value']},
          });
          first = null;
        }
      case 'callbacks':
        permissionRequest = id;
        for (final callback in [
          (101, 'session/request_permission'),
          (102, 'fs/write_text_file'),
          (103, 'terminal/create'),
        ]) {
          send({
            'id': callback.$1,
            'method': callback.$2,
            'params': <String, Object?>{},
          });
        }
      case null:
        callbacks.add(input);
        if (callbacks.length == 3) {
          send({
            'id': permissionRequest,
            'result': {'callbacks': callbacks},
          });
        }
      case 'malformed':
        stdout.writeln('{invalid');
      case 'invalid_result':
        send({
          'id': id,
          'result': ['unexpected array'],
        });
      case 'disconnect':
        exit(0);
      case 'timeout':
        break;
      default:
        send({'id': id, 'result': <String, Object?>{}});
    }
  }
}
