import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profiles_sheet.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'profiles sheet filters profiles and returns the selected open result',
    (tester) async {
      final defaultProfile = defaultTerminalProfile().copyWith(
        tags: const ['local', 'daily'],
      );
      final vt220Profile = vt220TerminalProfile().copyWith(
        name: 'Legacy Host',
        tags: const ['legacy', 'prod'],
      );
      ProfilesSheetResult? result;

      await _pumpProfilesSheetHarness(
        tester,
        profiles: [defaultProfile, vt220Profile],
        effectiveDefaultProfileId: defaultProfile.id,
        onClosed: (value) => result = value,
      );

      expect(find.textContaining('Default profile'), findsOneWidget);
      expect(
        find.byKey(Key('profile-entry-${defaultProfile.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('profile-entry-${vt220Profile.id}')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('profiles-search-field')))
            .autofocus,
        isTrue,
      );

      await tester.enterText(
        find.byKey(const Key('profiles-search-field')),
        'legacy',
      );
      await tester.pump();

      expect(
        find.byKey(Key('profile-entry-${defaultProfile.id}')),
        findsNothing,
      );
      expect(
        find.byKey(Key('profile-entry-${vt220Profile.id}')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(Key('profile-entry-${vt220Profile.id}')));
      await tester.pumpAndSettle();

      expect(result, isA<OpenProfileResult>());
      expect((result! as OpenProfileResult).profile.id, vt220Profile.id);
    },
  );

  testWidgets('profiles search does not summon the keyboard on iOS', (
    tester,
  ) async {
    await _pumpProfilesSheetHarness(
      tester,
      profiles: [defaultTerminalProfile()],
      effectiveDefaultProfileId: defaultTerminalProfile().id,
      platform: TargetPlatform.iOS,
      onClosed: (_) {},
    );

    final searchField = tester.widget<TextField>(
      find.byKey(const Key('profiles-search-field')),
    );
    expect(searchField.autofocus, isFalse);
    expect(find.bySemanticsIdentifier('profiles-search-field'), findsOneWidget);
  });

  testWidgets('profiles empty state fits above a landscape iPhone keyboard', (
    tester,
  ) async {
    const surfaceSize = Size(844, 390);
    const keyboardHeight = 216.0;
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.reset);

    await _pumpProfilesSheetHarness(
      tester,
      profiles: const <TerminalProfile>[],
      effectiveDefaultProfileId: null,
      platform: TargetPlatform.iOS,
      onClosed: (_) {},
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('profiles-search-field')));
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardHeight * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profiles-empty-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profiles sheet edit affordance returns the selected edit result',
    (tester) async {
      final profile = defaultTerminalProfile().copyWith(
        name: 'Workspace Shell',
      );
      ProfilesSheetResult? result;

      await _pumpProfilesSheetHarness(
        tester,
        profiles: [profile],
        effectiveDefaultProfileId: profile.id,
        onClosed: (value) => result = value,
      );

      await tester.tap(find.byTooltip('Edit Workspace Shell'));
      await tester.pumpAndSettle();

      expect(result, isA<EditProfileResult>());
      expect((result! as EditProfileResult).profile.id, profile.id);
    },
  );

  testWidgets('profiles New asks for local shell or SSH session', (
    tester,
  ) async {
    final profile = defaultTerminalProfile();
    ProfilesSheetResult? result;

    await _pumpProfilesSheetHarness(
      tester,
      profiles: [profile],
      effectiveDefaultProfileId: profile.id,
      onClosed: (value) => result = value,
    );

    await tester.tap(find.byKey(const Key('profiles-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profiles-create-local')), findsOneWidget);
    expect(find.byKey(const Key('profiles-create-ssh')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profiles-create-ssh')));
    await tester.pumpAndSettle();

    expect(result, isA<CreateProfileResult>());
    expect(
      (result! as CreateProfileResult).connectionType,
      NewProfileConnectionType.sshSession,
    );
  });

  testWidgets('local-only profiles allow local creation but not custom SSH', (
    tester,
  ) async {
    final local = defaultTerminalProfile();
    final ssh = local.copyWith(
      id: 'hidden-ssh',
      name: 'Hidden SSH',
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: 'ssh.example.test',
        user: 'developer',
      ),
    );

    await _pumpProfilesSheetHarness(
      tester,
      profiles: <TerminalProfile>[local, ssh],
      effectiveDefaultProfileId: local.id,
      customSshProfilesEnabled: false,
      onClosed: (_) {},
    );

    expect(find.byKey(const Key('profile-entry-hidden-ssh')), findsNothing);
    await tester.tap(find.byKey(const Key('profiles-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profiles-create-local')), findsOneWidget);
    expect(find.byKey(const Key('profiles-create-ssh')), findsNothing);
  });

  testWidgets('iPhone remote mode offers SSH creation without local shell', (
    tester,
  ) async {
    ProfilesSheetResult? result;
    await _pumpProfilesSheetHarness(
      tester,
      profiles: const <TerminalProfile>[],
      effectiveDefaultProfileId: null,
      platform: TargetPlatform.iOS,
      localShellProfilesEnabled: false,
      onClosed: (value) => result = value,
    );

    expect(find.text('No SSH profiles yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profiles-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profiles-create-local')), findsNothing);
    expect(
      result,
      isA<CreateProfileResult>().having(
        (value) => value.connectionType,
        'connection type',
        NewProfileConnectionType.sshSession,
      ),
    );
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets(
    'iPhone without a data service does not offer unusable profile types',
    (tester) async {
      final local = defaultTerminalProfile();
      final ssh = local.copyWith(
        id: 'hidden-ssh',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'ssh.example.test',
          user: 'developer',
        ),
      );

      await _pumpProfilesSheetHarness(
        tester,
        profiles: <TerminalProfile>[local, ssh],
        effectiveDefaultProfileId: null,
        platform: TargetPlatform.iOS,
        localShellProfilesEnabled: false,
        customSshProfilesEnabled: false,
        onClosed: (_) {},
      );

      expect(find.byKey(const Key('profiles-search-field')), findsNothing);
      expect(find.text('No saved profiles'), findsOneWidget);
      expect(
        find.text(
          'Connect a remote data service to create and sync SSH profiles.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('profiles-create')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(Key('profile-entry-${local.id}')), findsNothing);
      expect(find.byKey(const Key('profile-entry-hidden-ssh')), findsNothing);
    },
  );

  testWidgets(
    'profiles sheet delete affordance returns the selected delete result',
    (tester) async {
      final defaultProfile = defaultTerminalProfile();
      final profile = defaultTerminalProfile().copyWith(
        id: 'docker-ssh',
        name: 'Docker SSH',
      );
      ProfilesSheetResult? result;

      await _pumpProfilesSheetHarness(
        tester,
        profiles: [defaultProfile, profile],
        effectiveDefaultProfileId: defaultProfile.id,
        onClosed: (value) => result = value,
      );

      await tester.tap(find.byTooltip('Delete Docker SSH'));
      await tester.pumpAndSettle();

      expect(result, isA<DeleteProfileResult>());
      expect((result! as DeleteProfileResult).profile.id, profile.id);
    },
  );

  testWidgets('profiles sheet inherits shared list theming', (tester) async {
    final profile = defaultTerminalProfile().copyWith(
      name: 'Workspace Shell',
      tags: const ['work'],
    );

    await _pumpProfilesSheetHarness(
      tester,
      profiles: [profile],
      effectiveDefaultProfileId: profile.id,
      onClosed: (_) {},
    );

    final tileContext = tester.element(find.text('Workspace Shell'));
    final themedTile = ListTileTheme.of(tileContext);
    final shape = themedTile.shape! as RoundedRectangleBorder;
    final contentPadding = themedTile.contentPadding! as EdgeInsets;
    final shared = buildIanvsTerminalTheme(
      Brightness.light,
      platform: TargetPlatform.macOS,
    ).listTileTheme;
    expect(contentPadding, shared.contentPadding);
    expect(shape, shared.shape);
  });
}

Future<void> _pumpProfilesSheetHarness(
  WidgetTester tester, {
  required List<TerminalProfile> profiles,
  required String? effectiveDefaultProfileId,
  required ValueChanged<ProfilesSheetResult?> onClosed,
  TargetPlatform platform = TargetPlatform.macOS,
  bool localShellProfilesEnabled = true,
  bool customSshProfilesEnabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(Brightness.dark, platform: platform),
      darkTheme: buildIanvsTerminalTheme(Brightness.dark, platform: platform),
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onClosed(
                    await showModalBottomSheet<ProfilesSheetResult>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => ProfilesSheet(
                        profiles: profiles,
                        effectiveDefaultProfileId: effectiveDefaultProfileId,
                        localShellProfilesEnabled: localShellProfilesEnabled,
                        customSshProfilesEnabled: customSshProfilesEnabled,
                      ),
                    ),
                  );
                },
                child: const Text('Open profiles'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open profiles'));
  await tester.pumpAndSettle();
}
