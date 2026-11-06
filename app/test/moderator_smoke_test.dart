import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_truth/main.dart';
import 'package:ground_truth/models.dart';
import 'package:ground_truth/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _start(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  await tester.runAsync(() => appState.load());
  await appState.resetDemo();
  appState.theme = AppTheme.dark;
  appState.signInModerator();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const GroundTruthApp());
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1900, 1000), const Size(400, 800)]) {
    testWidgets('moderator renders all tabs and sheets at ${size.width}', (tester) async {
      await _start(tester, size);
      expect(find.text('Inbox'), findsWidgets);

      // Invite sheet with a QR code, from an Inbox alert.
      await tester.tap(find.text('Invite').first);
      await tester.pumpAndSettle();
      expect(find.text('Copy code'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      for (final tab in ['Risks', 'Experts', 'Inbox']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
      }

      // Invite from Experts without a country.
      await tester.tap(find.text('Experts').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite experts'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a country to get its invite QR code.'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // QR button in the app bar, on any tab.
      await tester.tap(find.byTooltip('Invite QR code for any country'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a country to get its invite QR code.'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Publish sheet from the R1043 review lists credited contributors.
      await tester.tap(find.text('Risks').last);
      await tester.pumpAndSettle();
      if (size.width < 900) {
        await tester.tap(find.textContaining('R1043').first);
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text('Publish'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(find.text('Contributors'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      if (size.width < 900) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // New risk form opens from the Risks tab.
      await tester.tap(find.text('Risks').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New risk'));
      await tester.pumpAndSettle();
      expect(find.text('Publish to experts'), findsOneWidget);
    });
  }

  testWidgets('expert entry pop-up is a centred dialog, Start opens the questions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => appState.load());
    await appState.resetDemo();
    appState.signInAs(appState.expertById('p1')!);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GroundTruthApp());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Not now')), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Start')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Trigger 1 of'), findsOneWidget);
  });

  test('saved risks persist, have no simulated answers, and can be deleted', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.load();
    final id = s.nextRiskId();
    s.saveRisk(Risk(
      custom: true, id: id, title: 'Test risk', type: 'New emerging risk', country: 'Chad', rationale: 'Because.',
      probabilityIdx: 3, impact: 4, level: 'High', trend: '', status: 'Active', exposure: '', needs: '',
      materialisation: '', triggers: const [Trigger(id: 'T1', title: 'Trigger one', description: '')],
    ));
    expect(s.respondents(s.byId(id)!), isEmpty);
    expect(s.panelForRisk(s.byId(id)!).length, greaterThanOrEqualTo(minPanel));

    final again = AppState();
    await again.load();
    expect(again.byId(id)?.title, 'Test risk');
    expect(again.byId(id)?.triggers.single.title, 'Trigger one');

    again.deleteRisk(again.byId(id)!);
    final third = AppState();
    await third.load();
    expect(third.byId(id), isNull);
  });

  test('public view JSON has aggregates only', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.load();
    final m = jsonDecode(s.publicViewJson([s.byId('R1043')!])) as Map<String, dynamic>;
    final r = (m['risks'] as List).single as Map<String, dynamic>;
    expect(r['published'], isTrue);
    final q = (r['questions'] as List).first as Map<String, dynamic>;
    expect((q['likelihood']['distribution_1_5'] as List).length, 5);
    final text = jsonEncode(m);
    for (final e in s.experts) {
      expect(text.contains(e.pseudonym), isFalse);
    }
    expect(text.contains('Smuggling routes'), isFalse); // no comments
    expect(inviteCodeFor('Kenya'), inviteCodeFor('Kenya'));

    // With credits: only experts who agreed, by their chosen name.
    final r1043 = s.byId('R1043')!;
    final withNames = (jsonDecode(s.publicViewJson([r1043], credits: true))['risks'] as List).single as Map<String, dynamic>;
    final names = [for (final c in withNames['contributors'] as List) c['name']];
    expect(names, contains('Fatimé Abakar')); // level 1: real name by default
    expect(names, contains('Nomad-55')); // level 2: pseudonym by default
    expect(names, isNot(contains('Delta-30'))); // level 3: anonymous by default
    expect(withNames['anonymous_contributors'], s.respondents(r1043).length - names.length);

    // An expert's choice for this risk overrides the profile default.
    s.signInAs(s.expertById('p1')!);
    s.submit(r1043, {for (final it in r1043.surveyItems) it.id: const ItemAnswer(agree: Agreement.yes, likelihood: 3, severity: 3)},
        credit: Credit.anonymous);
    expect(s.creditsFor(r1043).map((c) => c.name), isNot(contains('Amina Haroun')));
    s.submit(r1043, {for (final it in r1043.surveyItems) it.id: const ItemAnswer(agree: Agreement.yes, likelihood: 3, severity: 3)},
        credit: Credit.pseudonym);
    expect(s.creditsFor(r1043).map((c) => c.name), contains('Harmattan-17'));
    expect(s.redeemInvite(inviteCodeFor('Kenya')), 'Kenya');
  });
}
