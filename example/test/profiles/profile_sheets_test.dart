import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/dynamic_profiles_sheet.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profiles_sheet.dart';
import 'package:app/ui/app_ui.dart';

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

  testWidgets('dynamic profiles sheet validates top-level JSON before import', (
    tester,
  ) async {
    DynamicProfilesImportResult? result;

    await _pumpDynamicProfilesSheetHarness(
      tester,
      onClosed: (value) => result = value,
    );

    await tester.enterText(
      find.byKey(const Key('dynamic-profiles-json-field')),
      jsonEncode(const ['not-an-object']),
    );
    await tester.tap(find.byKey(const Key('dynamic-profiles-import')));
    await tester.pump();

    expect(find.text('Top-level JSON must be an object.'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('dynamic profiles sheet returns imported profiles and warnings', (
    tester,
  ) async {
    DynamicProfilesImportResult? result;

    await _pumpDynamicProfilesSheetHarness(
      tester,
      onClosed: (value) => result = value,
    );

    await tester.enterText(
      find.byKey(const Key('dynamic-profiles-json-field')),
      jsonEncode({
        'Profiles': [
          {
            'Name': 'prod.example.com',
            'Guid': 'prod-host',
            'Custom Command': 'Yes',
            'Command': 'ssh prod.example.com',
            'Tags': ['ssh'],
          },
        ],
      }),
    );
    await tester.tap(find.byKey(const Key('dynamic-profiles-import')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.warningCount, 0);
    expect(result!.profiles.single.id, 'prod-host');
    expect(result!.profiles.single.name, 'prod.example.com');
    expect(result!.profiles.single.tags, const ['ssh', 'Dynamic']);
    expect(result!.profiles.single.args, const ['-lc', 'ssh prod.example.com']);
  });
}

Future<void> _pumpProfilesSheetHarness(
  WidgetTester tester, {
  required List<TerminalProfile> profiles,
  required String? effectiveDefaultProfileId,
  required ValueChanged<ProfilesSheetResult?> onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildFluttermTheme(Brightness.dark),
      darkTheme: buildFluttermTheme(Brightness.dark),
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

Future<void> _pumpDynamicProfilesSheetHarness(
  WidgetTester tester, {
  required ValueChanged<DynamicProfilesImportResult?> onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildFluttermTheme(Brightness.dark),
      darkTheme: buildFluttermTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onClosed(
                    await showModalBottomSheet<DynamicProfilesImportResult>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => const DynamicProfilesSheet(),
                    ),
                  );
                },
                child: const Text('Open dynamic profiles'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open dynamic profiles'));
  await tester.pumpAndSettle();
}
