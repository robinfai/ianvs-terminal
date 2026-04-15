import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';

class _TestProfileRepository extends ProfileRepository {
  _TestProfileRepository(this._document);

  TerminalProfilesDocument _document;

  @override
  Future<TerminalProfilesDocument> load() async => _document;

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    _document = document;
  }
}

class _TestSessionController extends SessionController {
  @override
  SessionState build() {
    return SessionState.initial();
  }
}

void main() {
  test('session lifecycle updates tabs and active session', () {
    final coreClient = TerminalCoreClient(FakeCoreBindings());
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    expect(container.read(sessionControllerProvider).tabs, isEmpty);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    final first = container.read(sessionControllerProvider).activeSessionId;
    expect(first, isNotNull);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));
    final second = container.read(sessionControllerProvider).activeSessionId;
    expect(second, isNotNull);
    expect(second, isNot(equals(first)));

    controller.activateSession(first!);
    expect(container.read(sessionControllerProvider).activeSessionId, first);

    controller.closeSession(first);
    final afterCloseFirst = container.read(sessionControllerProvider);
    expect(afterCloseFirst.tabs, hasLength(1));
    expect(afterCloseFirst.activeSessionId, second);

    controller.closeSession(second!);
    final afterCloseSecond = container.read(sessionControllerProvider);
    expect(afterCloseSecond.tabs, isEmpty);
    expect(afterCloseSecond.activeSessionId, isNull);
  });

  test('closing inactive session keeps current active session', () {
    final coreClient = TerminalCoreClient(FakeCoreBindings());
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final first = container.read(sessionControllerProvider).activeSessionId!;
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    final second = container
        .read(sessionControllerProvider)
        .tabs
        .last
        .sessionId;
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-3'));
    final third = container.read(sessionControllerProvider).activeSessionId!;

    expect(third, isNotNull);
    expect(third, isNot(equals(first)));
    expect(third, isNot(equals(second)));

    controller.activateSession(first);
    expect(container.read(sessionControllerProvider).activeSessionId, first);

    controller.closeSession(second);
    final afterCloseInactive = container.read(sessionControllerProvider);
    expect(afterCloseInactive.tabs, hasLength(2));
    expect(
      afterCloseInactive.tabs.any((tab) => tab.sessionId == second),
      isFalse,
    );
    expect(afterCloseInactive.activeSessionId, first);
  });

  test('resizeActiveSession dedupes identical size requests', () {
    final coreBindings = FakeCoreBindings();
    final coreClient = TerminalCoreClient(coreBindings);
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.resizeActiveSession(const Size(640, 480), 2.0);
    expect(coreBindings.resizeCalls, hasLength(1));

    controller.resizeActiveSession(const Size(640, 480), 2.0);
    expect(
      coreBindings.resizeCalls,
      hasLength(1),
      reason: 'duplicate call skipped',
    );

    controller.resizeActiveSession(const Size(644, 480), 2.0);
    expect(coreBindings.resizeCalls, hasLength(2));

    final last = coreBindings.resizeCalls.last;
    expect(last[0], equals(int.parse(sessionId)));
    expect(last[1], greaterThan(0));
    expect(last[2], greaterThan(0));
    expect(last[3], greaterThan(0));
    expect(last[4], greaterThan(0));
  });
}
