/// Identity and anonymity rules.
///
/// Principle: individual contributions are never shown to the public.
/// Every screen that shows an expert's name goes through [displayName];
/// nothing else in the UI reads [Expert.realName] or [Expert.pseudonym]
/// for display (the profile editor only edits your own fields).
library;

enum Anonymity {
  /// Level 1: ACAPS knows your real name; colleagues see your pseudonym.
  knownToAcaps,

  /// Level 2: everyone, including ACAPS, sees only your pseudonym.
  pseudonymous,

  /// Level 3: nobody sees who you are. Your real name is deleted.
  anonymous,
}

extension AnonymityText on Anonymity {
  int get number => index + 1;

  String get label => switch (this) {
        Anonymity.knownToAcaps => 'Known to ACAPS',
        Anonymity.pseudonymous => 'Known to colleagues by pseudonym',
        Anonymity.anonymous => 'Fully anonymous',
      };

  String get description => switch (this) {
        Anonymity.knownToAcaps =>
          'ACAPS moderators see your real name. Colleagues see only your pseudonym.',
        Anonymity.pseudonymous =>
          'Everyone, including ACAPS, sees only your pseudonym. Your name is kept only to verify your account.',
        Anonymity.anonymous =>
          'Nobody sees who wrote your input, not even ACAPS. Your real name is deleted from the database.',
      };

  bool get needsRealName => this != Anonymity.anonymous;

  String get seenByAcaps => switch (this) {
        Anonymity.knownToAcaps => 'Real name',
        Anonymity.pseudonymous => 'Pseudonym',
        Anonymity.anonymous => 'Nothing',
      };

  String get seenByPeers => switch (this) {
        Anonymity.anonymous => 'Nothing',
        _ => 'Pseudonym',
      };
}

const anonymousName = 'Anonymous expert';

/// Deterministic string hash, kept small so it is identical on web and native.
int stableHash(String s) =>
    s.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) % 1000003);

/// An expert record as stored in the database. All demo experts are synthetic.
class Expert {
  final String id;

  /// Null whenever [level] is [Anonymity.anonymous]: the name is deleted, not hidden.
  String? realName;
  String pseudonym;
  Anonymity level;
  String homeCountry;
  Set<String> interests;
  bool onRating;
  bool notifications;

  /// Colleagues from other countries see "Anonymous expert" instead of the
  /// pseudonym. Colleagues from [homeCountry] and ACAPS are unaffected.
  bool hideFromOtherCountries;

  /// Synthetic panel member whose history is simulated.
  final bool simulated;

  /// Selectable on the demo login list.
  final bool persona;

  /// Simulation only: how often they answer, and how sharp their forecasts are.
  final double participation;
  final double skill;

  Expert({
    required this.id,
    required this.realName,
    required this.pseudonym,
    required this.level,
    required this.homeCountry,
    Set<String>? interests,
    this.onRating = true,
    this.notifications = true,
    this.hideFromOtherCountries = false,
    this.simulated = false,
    this.persona = false,
    this.participation = 0.8,
    this.skill = 0.5,
  }) : interests = interests ?? {} {
    if (level == Anonymity.anonymous) realName = null;
  }

  Set<String> get countries => {homeCountry, ...interests};

  bool inPanel(String country) => countries.contains(country);

  /// Changes the anonymity level. Going to level 3 deletes the real name.
  /// Going from level 3 to level 1 or 2 requires a new [name].
  void setLevel(Anonymity next, {String? name}) {
    if (next == Anonymity.anonymous) {
      realName = null;
    } else {
      final n = name?.trim() ?? '';
      if (n.isNotEmpty) {
        realName = n;
      } else if (realName == null) {
        throw ArgumentError('A real name is required for level ${next.number}.');
      }
    }
    level = next;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'real_name': realName,
        'pseudonym': pseudonym,
        'anonymity_level': level.number,
        'home_country': homeCountry,
        'interest_countries': interests.toList()..sort(),
        'on_rating': onRating,
        'notifications': notifications,
        'hide_from_other_countries': hideFromOtherCountries,
        'simulated': simulated,
        'persona': persona,
        'participation': participation,
        'skill': skill,
      };

  factory Expert.fromJson(Map<String, dynamic> m) => Expert(
        id: m['id'] as String,
        realName: m['real_name'] as String?,
        pseudonym: m['pseudonym'] as String,
        level: Anonymity.values[((m['anonymity_level'] as num).toInt() - 1).clamp(0, 2)],
        homeCountry: m['home_country'] as String,
        interests: {...((m['interest_countries'] as List?) ?? const []).cast<String>()},
        onRating: m['on_rating'] != false,
        notifications: m['notifications'] != false,
        hideFromOtherCountries: m['hide_from_other_countries'] == true,
        simulated: m['simulated'] == true,
        persona: m['persona'] == true,
        participation: (m['participation'] as num?)?.toDouble() ?? 0.8,
        skill: (m['skill'] as num?)?.toDouble() ?? 0.5,
      );
}

enum ViewerRole { expert, moderator, public }

/// Who is looking at the screen.
class Viewer {
  final ViewerRole role;
  final Expert? expert;

  const Viewer._(this.role, this.expert);
  const Viewer.expert(Expert e) : this._(ViewerRole.expert, e);
  static const moderator = Viewer._(ViewerRole.moderator, null);
  static const public = Viewer._(ViewerRole.public, null);

  bool get isModerator => role == ViewerRole.moderator;
}

/// The one place that decides which name of [expert] the [viewer] may see.
String displayName(Expert expert, Viewer viewer) {
  switch (viewer.role) {
    case ViewerRole.public:
      return anonymousName;
    case ViewerRole.moderator:
      return switch (expert.level) {
        Anonymity.knownToAcaps => expert.realName ?? expert.pseudonym,
        Anonymity.pseudonymous => expert.pseudonym,
        Anonymity.anonymous => anonymousName,
      };
    case ViewerRole.expert:
      final isSelf = viewer.expert?.id == expert.id;
      if (expert.level == Anonymity.anonymous) {
        return isSelf ? 'You (anonymous)' : anonymousName;
      }
      if (!isSelf && expert.hideFromOtherCountries && viewer.expert?.homeCountry != expert.homeCountry) {
        return anonymousName;
      }
      return expert.pseudonym;
  }
}

/// Where a group of experts comes from, split into the risk's own
/// country (or countries) and everywhere else. Sorted by count.
({List<({String country, int n})> local, List<({String country, int n})> other}) splitByRiskCountry(
    Iterable<Expert> experts, List<String> riskCountries) {
  final counts = <String, int>{};
  for (final e in experts) {
    counts[e.homeCountry] = (counts[e.homeCountry] ?? 0) + 1;
  }
  final all = [for (final e in counts.entries) (country: e.key, n: e.value)]
    ..sort((a, b) => b.n != a.n ? b.n.compareTo(a.n) : a.country.compareTo(b.country));
  return (
    local: all.where((x) => riskCountries.contains(x.country)).toList(),
    other: all.where((x) => !riskCountries.contains(x.country)).toList(),
  );
}

String countryList(List<({String country, int n})> xs) => xs.map((x) => '${x.country} ${x.n}').join(', ');

/// Multi-line text for the agree/disagree tooltip.
String describeSplit(Iterable<Expert> experts, List<String> riskCountries) {
  final s = splitByRiskCountry(experts, riskCountries);
  if (s.local.isEmpty && s.other.isEmpty) return 'No one yet';
  final localN = s.local.fold(0, (a, x) => a + x.n);
  final otherN = s.other.fold(0, (a, x) => a + x.n);
  return [
    'From ${riskCountries.join(', ')}: $localN',
    if (otherN > 0) 'From other countries: $otherN (${countryList(s.other)})',
  ].join('\n');
}

/// How [e] appears to someone else in [role], e.g. for "who sees what" previews.
/// For colleagues, [sameCountry] picks a colleague from e's home country.
String nameSeenBy(Expert e, ViewerRole role, {bool sameCountry = false}) => displayName(
      e,
      switch (role) {
        ViewerRole.expert => Viewer.expert(Expert(
            id: '\u0000colleague',
            realName: null,
            pseudonym: '',
            level: Anonymity.anonymous,
            homeCountry: sameCountry ? e.homeCountry : '\u0000elsewhere',
          )),
        ViewerRole.moderator => Viewer.moderator,
        ViewerRole.public => Viewer.public,
      },
    );
