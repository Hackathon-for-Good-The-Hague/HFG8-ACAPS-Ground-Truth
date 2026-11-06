import 'package:ground_truth/identity.dart';

void check(bool ok, String what) {
  print('${ok ? 'PASS' : 'FAIL'}  $what');
  if (!ok) throw StateError(what);
}

Expert e(String id, Anonymity l, {String c = 'Chad'}) =>
    Expert(id: id, realName: 'Real Name', pseudonym: 'P-$id', level: l, homeCountry: c);

void main() {
  final l1 = e('a', Anonymity.knownToAcaps), l2 = e('b', Anonymity.pseudonymous), l3 = e('c', Anonymity.anonymous);
  final peer = Viewer.expert(e('x', Anonymity.pseudonymous));
  check([l1, l2, l3].every((x) => displayName(x, Viewer.public) == anonymousName), 'public sees nobody');
  check(displayName(l1, Viewer.moderator) == 'Real Name', 'moderator sees level-1 real name');
  check(displayName(l2, Viewer.moderator) == 'P-b', 'moderator sees level-2 pseudonym');
  check(displayName(l3, Viewer.moderator) == anonymousName, 'moderator sees nothing at level 3');
  check(displayName(l1, peer) == 'P-a' && displayName(l3, peer) == anonymousName, 'peers never see real names');
  check(l3.realName == null && l3.toJson()['real_name'] == null, 'level 3 stores no name');
  final d = e('d', Anonymity.knownToAcaps)..setLevel(Anonymity.anonymous);
  check(d.realName == null, 'switching to level 3 deletes the name');
  var threw = false;
  try { d.setLevel(Anonymity.pseudonymous); } catch (_) { threw = true; }
  check(threw, 'leaving level 3 without a name is refused');
  d.setLevel(Anonymity.pseudonymous, name: 'New Name');
  check(d.realName == 'New Name', 'leaving level 3 with a name stores it');
  final xs = [for (var i = 0; i < 3; i++) e('c$i', Anonymity.pseudonymous), e('s', Anonymity.pseudonymous, c: 'Sudan'), e('k', Anonymity.pseudonymous, c: 'Kenya')];
  check(describeSplit(xs, ['Chad']) == 'From Chad: 3\nFrom other countries: 2 (Kenya 1, Sudan 1)', 'risk country vs other countries split');
  check(describeSplit(const [], ['Chad']) == 'No one yet', 'empty split');
  final hid = e('h', Anonymity.pseudonymous)..hideFromOtherCountries = true;
  check(displayName(hid, Viewer.expert(e('y', Anonymity.pseudonymous))) == 'P-h', 'hide abroad: same-country colleague sees pseudonym');
  check(displayName(hid, Viewer.expert(e('z', Anonymity.pseudonymous, c: 'Sudan'))) == anonymousName, 'hide abroad: other-country colleague sees nothing');
  check(displayName(hid, Viewer.moderator) == 'P-h', 'hide abroad: ACAPS unaffected');
  check(nameSeenBy(hid, ViewerRole.expert, sameCountry: true) == 'P-h' && nameSeenBy(hid, ViewerRole.expert) == anonymousName, 'nameSeenBy sameCountry');
  check(nameSeenBy(l2, ViewerRole.expert) == 'P-b' && nameSeenBy(l3, ViewerRole.expert) == anonymousName, 'nameSeenBy');
}
