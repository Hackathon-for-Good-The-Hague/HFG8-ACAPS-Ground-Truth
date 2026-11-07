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

      // Inbox badge counts new comments only.
      expect(find.descendant(of: find.byType(Badge), matching: find.text('${appState.commentsToReview}')), findsWidgets);

      // Invite from an Inbox country: its QR code straight away, no country picker.
      await tester.tap(find.text('Invite').first);
      await tester.pumpAndSettle();
      expect(find.text('Copy code'), findsOneWidget);
      expect(find.textContaining('Invite experts to '), findsOneWidget);
      expect(find.text('Pick a country to get its invite QR code.'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      for (final tab in ['Risks', 'Comments', 'Experts', 'Profile', 'Inbox']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
      }

      // Experts tab: no second QR button.
      await tester.tap(find.text('Experts').last);
      await tester.pumpAndSettle();
      expect(find.text('Invite experts'), findsNothing);

      // Profile: this moderator's name and display settings.
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('Sarah Okafor'), findsOneWidget);
      expect(find.text('Text size'), findsOneWidget);

      // Comments tab: review actions for the risk with most new comments.
      await tester.tap(find.text('Comments').last);
      await tester.pumpAndSettle();
      if (size.width < 900) {
        await tester.tap(find.textContaining('R1043 ·').first);
        await tester.pumpAndSettle();
      }
      expect(find.text('Mark reviewed'), findsWidgets);
      if (size.width < 900) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

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

      // A trigger's comment chip on the Risks tab opens those comments.
      await tester.tap(find.text('Risks').last);
      await tester.pumpAndSettle();
      if (size.width < 900) {
        await tester.tap(find.textContaining('R1043').first);
        await tester.pumpAndSettle();
      }
      final chip = find.textContaining('· open');
      for (var i = 0; i < 30 && chip.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(chip.first);
      await tester.pumpAndSettle();
      await tester.tap(chip.first);
      await tester.pumpAndSettle();
      // Scrolled to that trigger's comments, with their per-comment actions.
      expect(find.text('ACTIONS FOR THIS COMMENT ONLY'), findsWidgets);
      if (size.width < 900) {
        await tester.pageBack();
        await tester.pumpAndSettle();
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

  testWidgets('"Not now" hides the banner, says so, and can be undone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => appState.load());
    await appState.resetDemo();
    final p1 = appState.expertById('p1')!;
    appState.signInAs(p1);
    appState.autoOpened.add('p1|${appState.pendingNotification!.id}'); // skip the entry pop-up
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GroundTruthApp());
    await tester.pumpAndSettle();

    final r = appState.pendingNotification!;
    expect(find.text(r.title), findsOneWidget); // the banner names the risk
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(appState.pendingNotification, isNull);
    expect(appState.isSkipped(r), isTrue);
    expect(find.text('Skipped'), findsOneWidget); // tag on the risk card
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(appState.isSkipped(r), isFalse);
    expect(appState.pendingNotification?.id, r.id);

    // The message closes by itself after 5 seconds.
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('experts never see which moderator handled their comment', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => appState.load());
    await appState.resetDemo();
    appState.signInAs(appState.expertById('p1')!); // p1's comment s5 was marked useful and used by Sarah Okafor
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GroundTruthApp());
    await tester.pumpAndSettle();
    if (find.text('Not now').evaluate().isNotEmpty) {
      await tester.tap(find.text('Not now').first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.history)); // Profile -> My forecasts
    await tester.pumpAndSettle();
    // Scroll through the whole list, checking each screenful for moderator names.
    final flag = find.textContaining('Marked useful by ACAPS');
    var seen = false;
    for (var i = 0; i < 40; i++) {
      seen |= flag.evaluate().isNotEmpty;
      for (final m in moderators) {
        expect(find.textContaining(m.name), findsNothing);
        expect(find.textContaining(m.shortName), findsNothing);
      }
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(seen, isTrue);
  });

  test('closed risks are read-only and earn no points', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.load();
    s.register(level: Anonymity.pseudonymous, realName: 'Test Person', pseudonym: 'Tester', homeCountry: 'Chad',
        interests: {'Sudan'}, notifications: true, onRating: true);
    final closed = s.archiveForMe().first;
    final before = s.statsOf(s.me!).points;

    // The archive has every closed risk, not only my countries; mine first.
    expect(s.archiveForMe().length, s.risks.where((r) => r.isResolved).length);
    expect(s.archiveForMe().any((r) => !s.relevantTo(s.me!, r)), isTrue);
    expect(s.relevantTo(s.me!, closed), isTrue);

    // Answered closed risks stay in the archive too.
    s.signInAs(s.expertById('p2')!);
    expect(s.archiveForMe(), isNotEmpty);
    expect(s.archiveForMe().where((r) => s.responseOf(s.me!, r) != null), isNotEmpty);
    s.signInAs(s.experts.last);
    s.submit(closed, {for (final it in closed.surveyItems) it.id: const ItemAnswer(agree: Agreement.yes, likelihood: 5, severity: 3)});
    expect(s.responseOf(s.me!, closed), isNull);
    expect(s.statsOf(s.me!).points, before);
  });

  test('moderators have own accounts, signed actions and display settings', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.load();
    s.signInModerator('m2');
    expect(s.moderator?.name, 'Tomás Lindqvist');
    s.setTheme(AppTheme.dark);
    s.setTextScale(1.3);
    final c = s.comments.firstWhere((c) => c.needsReview);
    final before = s.commentsToReview;
    s.toggleUseful(c);
    expect(c.usefulBy, 'm2');
    expect(c.reviewedBy, 'm2');
    expect(s.commentsToReview, before - 1);
    expect(s.activityOf(s.moderator!).useful, greaterThanOrEqualTo(1));

    s.signInModerator('m3');
    expect(s.theme, AppTheme.system);
    expect(s.textScale, 1.0);

    // Persisted: back to m2 after a restart.
    final again = AppState();
    await again.load();
    expect(again.moderator?.id, 'm3');
    again.signInModerator('m2');
    expect(again.theme, AppTheme.dark);
    expect(again.textScale, 1.3);
    expect(again.comments.firstWhere((x) => x.id == c.id).usefulBy, 'm2');
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
