import 'package:flutter_test/flutter_test.dart';
import 'package:ground_truth/models.dart';
import 'package:ground_truth/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Expert _e(String id, Anonymity level, {String? name = 'Real Name', String country = 'Chad'}) =>
    Expert(id: id, realName: name, pseudonym: 'Pseudo-$id', level: level, homeCountry: country);

void main() {
  group('displayName', () {
    final l1 = _e('a', Anonymity.knownToAcaps);
    final l2 = _e('b', Anonymity.pseudonymous);
    final l3 = _e('c', Anonymity.anonymous);
    final peer = Viewer.expert(_e('x', Anonymity.pseudonymous));

    test('public never sees anyone', () {
      for (final e in [l1, l2, l3]) {
        expect(displayName(e, Viewer.public), anonymousName);
      }
    });

    test('moderator sees real name only at level 1', () {
      expect(displayName(l1, Viewer.moderator), 'Real Name');
      expect(displayName(l2, Viewer.moderator), 'Pseudo-b');
      expect(displayName(l3, Viewer.moderator), anonymousName);
    });

    test('colleagues never see real names', () {
      expect(displayName(l1, peer), 'Pseudo-a');
      expect(displayName(l2, peer), 'Pseudo-b');
      expect(displayName(l3, peer), anonymousName);
    });
  });

  group('anonymity levels', () {
    test('level 3 never stores a real name', () {
      expect(_e('n', Anonymity.anonymous).realName, isNull);
    });

    test('switching to level 3 deletes the name', () {
      final e = _e('d', Anonymity.knownToAcaps)..setLevel(Anonymity.anonymous);
      expect(e.realName, isNull);
      expect(e.toJson()['real_name'], isNull);
    });

    test('leaving level 3 requires the name again', () {
      final e = _e('f', Anonymity.anonymous);
      expect(() => e.setLevel(Anonymity.pseudonymous), throwsArgumentError);
      e.setLevel(Anonymity.pseudonymous, name: 'New Name');
      expect(e.realName, 'New Name');
    });
  });

  test('agree/disagree countries are split into risk country and others', () {
    final xs = [
      for (var i = 0; i < 3; i++) _e('c$i', Anonymity.pseudonymous, country: 'Chad'),
      _e('s1', Anonymity.pseudonymous, country: 'Sudan'),
      _e('k1', Anonymity.pseudonymous, country: 'Kenya'),
    ];
    expect(describeSplit(xs, ['Chad']), 'From Chad: 3\nFrom other countries: 2 (Kenya 1, Sudan 1)');
    expect(describeSplit(xs.take(3), ['Chad']), 'From Chad: 3');
    expect(describeSplit(const [], ['Chad']), 'No one yet');
  });

  group('store', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('R1043 survey: 3 trigger screens, 5 of 8 before you, 6 of 8 after', () async {
      final s = AppState();
      await s.load();
      expect(s.error, isNull);
      final r = s.byId('R1043')!;
      expect(r.surveyItems.length, 3);
      expect(s.panelForRisk(r).length, 8);
      expect(s.respondents(r).length, 5);

      expect(s.redeemInvite('nope'), isNull);
      expect(s.redeemInvite('gt-chad-7q4x'), 'Chad');
      s.signInAs(s.expertById('p1')!);
      expect(s.pendingNotification?.id, 'R1043');

      s.submit(r, {
        for (final it in r.surveyItems)
          it.id: ItemAnswer(agree: Agreement.partly, likelihood: 4, severity: 4, missing: it == r.surveyItems.first ? 'Watch Tiné' : ''),
      });
      expect(s.respondents(r).length, 6);
      expect(s.commentsOn(r).where((c) => c.authorId == 'p1').length, 1);
      expect(s.pendingNotification?.id, isNot('R1043'));
    });

    test('persona history has matured, scored forecasts', () async {
      final s = AppState();
      await s.load();
      final p1 = s.expertById('p1')!;
      final matured = s.responsesOf(p1).where((x) => s.byId(x.riskId)!.isResolved).toList();
      expect(matured, isNotEmpty);
      expect(s.scoreOf(matured.first), isNotNull);
      expect(s.rawExpertTable, contains('"real_name": null'));
      expect(s.thinPanels.any((p) => p.country == 'Cameroon' && p.n == 2), isTrue);
    });
  });
}
