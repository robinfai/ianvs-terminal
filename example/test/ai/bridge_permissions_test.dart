import 'package:app/features/ai/acp/bridge_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Scoped bridge access', () {
    late BridgePermissions permissions;
    setUp(() {
      permissions = BridgePermissions();
    });
    Map<String, Object?> request(String session) => {
      'sessionId': session,
      'toolCall': {'toolCallId': 'call'},
      'options': [
        {'kind': 'allow_always', 'optionId': 'always'},
        {'kind': 'allow_once', 'optionId': 'once'},
      ],
    };
    void observe(String server, String tool) => permissions.observe({
      'toolCallId': 'call',
      'rawInput': {'server': server, 'tool': tool},
      'status': 'in_progress',
    });
    test(
      'allows only one access to an observed Trail tool in the current session',
      () {
        observe('trail_terminal', 'run_command');
        expect(
          permissions.option(
            request('other'),
            session: 'current',
            active: true,
          ),
          isNull,
        );
        expect(
          permissions.option(
            request('current'),
            session: 'current',
            active: true,
          ),
          'once',
        );
        expect(
          permissions.option(
            request('current'),
            session: 'current',
            active: true,
          ),
          isNull,
        );
      },
    );
    test(
      'denies host tools, unknown tools, stale calls and inactive sessions',
      () {
        for (final target in [
          ('host', 'run_command'),
          ('trail_terminal', 'shell'),
        ]) {
          observe(target.$1, target.$2);
          expect(
            permissions.option(
              request('current'),
              session: 'current',
              active: true,
            ),
            isNull,
          );
        }
        observe('trail_terminal', 'read_screen');
        expect(
          permissions.option(
            request('current'),
            session: 'current',
            active: false,
          ),
          isNull,
        );
        permissions.observe({'toolCallId': 'call', 'status': 'completed'});
        expect(
          permissions.option(
            request('current'),
            session: 'current',
            active: true,
          ),
          isNull,
        );
      },
    );
    test('cancellation clears all bridge access', () {
      observe('trail_terminal', 'send_keys');
      permissions.clear();
      expect(
        permissions.option(
          request('current'),
          session: 'current',
          active: true,
        ),
        isNull,
      );
    });
  });
}
