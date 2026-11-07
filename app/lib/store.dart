import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'csv.dart';
import 'identity.dart';
import 'models.dart';

export 'identity.dart';

/// Demo invite codes, as printed on the QR codes ACAPS hands out.
const inviteCodes = {'GT-CHAD-7Q4X': 'Chad', 'GT-SDN-3K9M': 'Sudan'};

/// Invite code for a country panel: the printed demo code if there is one,
/// otherwise a stable generated one (same country, same code).
String inviteCodeFor(String country) {
  final printed = inviteCodes.entries.where((e) => e.value == country).firstOrNull?.key;
  if (printed != null) return printed;
  final letters = country.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var h = 7;
  for (final u in country.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  final tail = List.generate(4, (i) => alphabet[(h >> (i * 5)) % alphabet.length]).join();
  return 'GT-${letters.substring(0, min(4, letters.length))}-$tail';
}

/// Likelihood 1..5 -> probability used for Brier scoring.
const likelihoodProbs = [0.1, 0.3, 0.5, 0.7, 0.9];

double brier(int likelihood, bool happened) =>
    pow(likelihoodProbs[likelihood - 1] - (happened ? 1 : 0), 2).toDouble();

class Points {
  static const usefulComment = 25;
  static const usedComment = 50;
  static int forecast(double brier) => (100 * (1 - brier)).round();
}

/// Accuracy shown to experts: 100% = perfect, 0% = worst. Same as points per forecast.
int accuracyPct(double brier) => (100 * (1 - brier)).round();

/// Regions used by the rating filter (ACAPS-style groupings).
const regions = {
  'West & Central Africa': ['Benin', 'Cameroon', 'Central African Republic', 'Chad', 'Congo',
      'Democratic Republic of the Congo', 'Ghana', 'Ivory Coast', 'Mali', 'Mauritania', 'Niger', 'Nigeria', 'Togo'],
  'East & Southern Africa': ['Burundi', 'Ethiopia', 'Kenya', 'Madagascar', 'Mozambique', 'Rwanda', 'Somalia',
      'South Sudan', 'Sudan', 'Tanzania', 'Uganda', 'Zimbabwe'],
  'Middle East & North Africa': ['Algeria', 'Egypt', 'Iran', 'Iraq', 'Lebanon', 'Libya', 'Morocco', 'Palestine',
      'Syria', 'Tunisia', 'Turkey', 'Yemen'],
  'Asia & Pacific': ['Afghanistan', 'Bangladesh', 'Indonesia', 'Mongolia', 'Myanmar', 'Nepal', 'Papua New Guinea',
      'Philippines', 'Sri Lanka', 'Timor Leste'],
  'Americas': ['Colombia', 'Cuba', 'El Salvador', 'Guatemala', 'Haiti', 'Honduras', 'Mexico', 'Panama', 'Peru', 'Venezuela'],
  'Europe': ['Ukraine'],
};

String regionOf(String country) =>
    regions.entries.where((e) => e.value.contains(country)).firstOrNull?.key ?? 'Other';

enum RatingScope { country, region, all }

/// An ACAPS moderator account. Each moderator signs in separately, so their
/// actions on comments are attributed and their display settings are their
/// own. All moderators have the same permissions; there are no roles.
class Moderator {
  final String id;
  final String name;
  const Moderator({required this.id, required this.name});

  /// "Sarah Okafor" -> "Sarah O."
  String get shortName {
    final parts = name.split(' ');
    return parts.length < 2 ? name : '${parts.first} ${parts.last[0]}.';
  }
}

/// Synthetic moderator accounts (no real ACAPS staff).
const moderators = [
  Moderator(id: 'm1', name: 'Sarah Okafor'),
  Moderator(id: 'm2', name: 'Tomás Lindqvist'),
  Moderator(id: 'm3', name: 'Mei Tanaka'),
];

Moderator? moderatorById(String? id) => moderators.where((m) => m.id == id).firstOrNull;

enum AppTheme { system, light, dark, contrast }

extension AppThemeText on AppTheme {
  String get label => switch (this) {
        AppTheme.system => 'System',
        AppTheme.light => 'Light',
        AppTheme.dark => 'Dark',
        AppTheme.contrast => 'High contrast',
      };
}

/// Text size range, in 5% steps.
const minTextScale = 0.85, maxTextScale = 1.5, textScaleStep = 0.05;

double snapTextScale(double v) =>
    ((v.clamp(minTextScale, maxTextScale) / textScaleStep).round() * textScaleStep * 100).round() / 100;

/// Minimum panel size before the moderator is warned (same k as country display).
const minPanel = 3;
const minResolvedForBrier = 3;

enum Award { superEstimator, usefulInsight, cited, regular }

extension AwardText on Award {
  String get label => switch (this) {
        Award.superEstimator => 'Super estimator',
        Award.usefulInsight => 'Useful insight',
        Award.cited => 'Cited in analysis',
        Award.regular => 'Regular',
      };

  String get why => switch (this) {
        Award.superEstimator => 'Top 3 by Brier score (at least $minResolvedForBrier matured forecasts)',
        Award.usefulInsight => 'A moderator marked your comment as useful',
        Award.cited => 'Your comment was used in the analysis of another risk',
        Award.regular => 'Answered 5 or more risk surveys',
      };
}

class RatingRow {
  final Expert? expert; // null = ACAPS baseline
  final int points;
  final int resolved;
  final double? brier;
  final Set<Award> badges;

  const RatingRow({this.expert, required this.points, required this.resolved, this.brier, this.badges = const {}});
}

class RiskModStats {
  final int panel;
  final int answered;
  final int comments;
  final int toReview;
  final double? expertLikelihood;
  final int? acapsLikelihood;

  /// 0 = everyone agrees with ACAPS, 1 = everyone disagrees (partly counts half).
  final double disagreement;

  const RiskModStats({
    required this.panel,
    required this.answered,
    required this.comments,
    required this.toReview,
    required this.expertLikelihood,
    required this.acapsLikelihood,
    required this.disagreement,
  });

  double get responseRate => panel == 0 ? 0 : answered / panel;

  /// Experts' mean likelihood minus ACAPS (positive = experts see it as more likely).
  double? get gap => expertLikelihood == null || acapsLikelihood == null ? null : expertLikelihood! - acapsLikelihood!;
}

class PanelStats {
  final String country;
  final String region;
  final List<Expert> experts;
  final int activeRisks;
  final double? responseRate;
  const PanelStats({required this.country, required this.region, required this.experts, required this.activeRisks, required this.responseRate});
}

class ForecastScore {
  final double mine;
  final double acaps;
  final int points;
  const ForecastScore(this.mine, this.acaps, this.points);
}

class AppState extends ChangeNotifier {
  List<Risk> risks = [];
  bool loaded = false;
  String? error;
  SharedPreferences? _prefs;

  // ---- database (persisted) ----
  List<Expert> experts = [];
  final Map<String, Response> _responses = {}; // "$expertId|$riskId"
  List<Comment> comments = [];
  final Map<String, Set<String>> _skipped = {}; // expertId -> riskIds

  // ---- display settings (persisted separately; Reset demo keeps them) ----
  // Each account (expert or moderator) keeps its own theme and text size.
  // Accounts that never changed them use the device default, which is also
  // what the sign-in screens use.
  final Map<String, ({AppTheme theme, double scale})> _display = {};
  static const _deviceKey = 'device';

  String get _displayKey => sessionModeratorId ?? sessionExpertId ?? _deviceKey;

  ({AppTheme theme, double scale}) get _currentDisplay =>
      _display[_displayKey] ?? _display[_deviceKey] ?? (theme: AppTheme.system, scale: 1.0);

  AppTheme get theme => _currentDisplay.theme;
  double get textScale => _currentDisplay.scale;

  /// Sets the theme for the current account without saving (tests, previews).
  set theme(AppTheme t) => _display[_displayKey] = (theme: t, scale: textScale);

  /// Risk to open straight away, e.g. from a tapped push notification (?risk=R1043).
  String? deepLinkRisk;

  /// Risks already auto-opened this launch ("expertId|riskId"), so the pop-up shows once.
  final Set<String> autoOpened = {};

  void setTheme(AppTheme t) {
    _display[_displayKey] = (theme: t, scale: textScale);
    _saveUi();
    notifyListeners();
  }

  void setTextScale(double v) {
    _display[_displayKey] = (theme: theme, scale: snapTextScale(v));
    _saveUi();
    notifyListeners();
  }

  static const _uiKey = 'ground_truth_ui_v1';

  void _saveUi() => _prefs?.setString(
        _uiKey,
        jsonEncode({
          'accounts': {
            for (final e in _display.entries) e.key: {'theme': e.value.theme.name, 'scale': e.value.scale},
          },
        }),
      );

  void _restoreUi() {
    ({AppTheme theme, double scale}) parse(Map m) => (
          theme: AppTheme.values.firstWhere((t) => t.name == m['theme'], orElse: () => AppTheme.system),
          scale: snapTextScale((m['scale'] as num?)?.toDouble() ?? 1.0),
        );
    try {
      final raw = _prefs?.getString(_uiKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _display.clear();
      if (m['accounts'] is Map) {
        for (final e in (m['accounts'] as Map).entries) {
          _display[e.key as String] = parse(e.value as Map);
        }
      } else {
        _display[_deviceKey] = parse(m); // older format: one setting for the whole device
      }
    } catch (_) {}
  }

  /// The risk to open when entering the app: a notification deep link first,
  /// otherwise a new or updated risk not yet shown this launch.
  Risk? takeAutoOpen() {
    final e = me;
    if (e == null) return null;
    if (deepLinkRisk != null) {
      final r = byId(deepLinkRisk!);
      deepLinkRisk = null;
      if (r != null) return r;
    }
    final r = pendingNotification;
    if (r == null || !autoOpened.add('${e.id}|${r.id}')) return null;
    return r;
  }

  // ---- session (persisted) ----
  String? invitePanel;
  String? sessionExpertId;
  String? sessionModeratorId;

  bool get sessionModerator => sessionModeratorId != null;

  /// The moderator signed in, if any.
  Moderator? get moderator => moderatorById(sessionModeratorId);

  Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('assets/risk-radar-export.csv');
      final rows = parseCsv(raw);
      final header = rows.first.map((h) => h.trim()).toList();
      risks = rows.skip(1).where((r) => r.length > 1 && r[0].trim().isNotEmpty).map((r) {
        final m = <String, String>{};
        for (var i = 0; i < header.length; i++) {
          m[header[i]] = i < r.length ? r[i] : '';
        }
        return Risk.fromRow(m);
      }).toList();

      try {
        _prefs = await SharedPreferences.getInstance();
      } catch (_) {
        // Storage is optional: the app still works, it just won't remember.
      }
      _restoreUi();
      if (!_restore()) _seed();
    } catch (e) {
      error = '$e';
    }
    loaded = true;
    notifyListeners();
  }

  // =========================================================================
  // Session
  // =========================================================================

  Expert? get me => experts.where((e) => e.id == sessionExpertId).firstOrNull;

  Viewer get viewer => sessionModerator ? Viewer.moderator : (me == null ? Viewer.public : Viewer.expert(me!));

  bool get signedIn => sessionModerator || me != null;

  /// Returns the panel country, or null if the code is not a valid invite.
  String? redeemInvite(String code) {
    final c = code.trim().toUpperCase();
    final panel = inviteCodes[c] ?? countries.where((x) => inviteCodeFor(x) == c).firstOrNull;
    if (panel != null) {
      invitePanel = panel;
      _changed();
    }
    return panel;
  }

  void signInAs(Expert e) {
    sessionExpertId = e.id;
    sessionModeratorId = null;
    _changed();
  }

  void signInModerator([String id = 'm1']) {
    sessionExpertId = null;
    sessionModeratorId = moderatorById(id)?.id ?? moderators.first.id;
    _changed();
  }

  void signOut() {
    sessionExpertId = null;
    sessionModeratorId = null;
    _changed();
  }

  Expert register({
    required Anonymity level,
    required String? realName,
    required String pseudonym,
    required String homeCountry,
    required Set<String> interests,
    required bool notifications,
    required bool onRating,
    bool hideFromOtherCountries = false,
  }) {
    final e = Expert(
      id: 'u${DateTime.now().millisecondsSinceEpoch}',
      realName: level.needsRealName ? realName?.trim() : null,
      pseudonym: pseudonym.trim(),
      level: level,
      homeCountry: homeCountry,
      interests: interests..remove(homeCountry),
      notifications: notifications,
      onRating: onRating,
      hideFromOtherCountries: hideFromOtherCountries,
    );
    experts.add(e);
    signInAs(e);
    return e;
  }

  void updateMe(void Function(Expert e) f) {
    final e = me;
    if (e == null) return;
    f(e);
    e.interests.remove(e.homeCountry);
    _changed();
  }

  Future<void> resetDemo() async {
    await _prefs?.remove(_prefsKey);
    invitePanel = null;
    sessionExpertId = null;
    sessionModeratorId = null;
    _bannerDismissed.clear();
    risks.removeWhere((r) => r.custom);
    _seed();
    _statsCache.clear();
    notifyListeners();
  }

  // =========================================================================
  // Risks & panels
  // =========================================================================

  List<String> get countries {
    final s = <String>{};
    for (final r in risks) {
      s.addAll(riskCountries(r));
    }
    return s.toList()..sort();
  }

  static List<String> riskCountries(Risk r) =>
      r.country.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Risk? byId(String id) => risks.where((r) => r.id == id).firstOrNull;

  Expert? expertById(String id) => experts.where((e) => e.id == id).firstOrNull;

  List<Expert> panelFor(String country) => experts.where((e) => e.inPanel(country)).toList();

  /// Everyone on a panel for any of the risk's countries.
  List<Expert> panelForRisk(Risk r) {
    final cs = riskCountries(r);
    return experts.where((e) => cs.any(e.inPanel)).toList();
  }

  bool relevantTo(Expert e, Risk r) => riskCountries(r).any(e.inPanel);

  /// Active risks in my countries, demo risk first, unanswered first.
  List<Risk> activeForMe() {
    final e = me;
    if (e == null) return [];
    int score(Risk r) =>
        (r.id == 'R1043' ? 1000 : 0) + (r.inCountry(e.homeCountry) ? 100 : 0) + (r.level == 'High' ? 10 : 0);
    return risks.where((r) => r.isActive && r.probabilityIdx != null && relevantTo(e, r)).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
  }

  /// Every closed risk, whenever it closed and whether or not I answered it:
  /// read-only, to see what happened. My countries come first. New answers
  /// are not accepted and earn no points; a forecast made while the risk was
  /// open is still shown with its score.
  List<Risk> archiveForMe() {
    final e = me;
    if (e == null) return [];
    final closed = risks.where((r) => r.isResolved).toList();
    return [...closed.where((r) => relevantTo(e, r)), ...closed.where((r) => !relevantTo(e, r))];
  }

  /// Experts who pressed "Not now" this launch: the banner stays hidden until
  /// the next launch (deliberately not persisted).
  final Set<String> _bannerDismissed = {};

  /// The "ACAPS updated a risk" banner: first unanswered, unskipped active risk.
  Risk? get pendingNotification {
    final e = me;
    if (e == null || !e.notifications || _bannerDismissed.contains(e.id)) return null;
    return activeForMe().where((r) => responseOf(e, r) == null && !isSkipped(r)).firstOrNull;
  }

  bool isSkipped(Risk r) {
    final e = me;
    return e != null && (_skipped[e.id]?.contains(r.id) ?? false);
  }

  /// "Not now": the risk stays in the list, marked skipped, and the banner is
  /// hidden for the rest of this session.
  void skip(Risk r) {
    final e = me;
    if (e == null) return;
    (_skipped[e.id] ??= {}).add(r.id);
    _bannerDismissed.add(e.id);
    _changed();
  }

  void undoSkip(Risk r) {
    final e = me;
    if (e == null) return;
    _skipped[e.id]?.remove(r.id);
    _bannerDismissed.remove(e.id);
    _changed();
  }

  // =========================================================================
  // Responses
  // =========================================================================

  Response? responseOf(Expert e, Risk r) => _responses['${e.id}|${r.id}'] ?? _simulated(e, r);

  List<Response> responsesOf(Expert e) {
    final out = <Response>[];
    for (final r in risks) {
      final resp = responseOf(e, r);
      if (resp != null) out.add(resp);
    }
    out.sort((a, b) => (b.editedAt ?? b.answeredAt).compareTo(a.editedAt ?? a.answeredAt));
    return out;
  }

  void submit(Risk r, Map<String, ItemAnswer> items, {Credit? credit}) {
    final e = me;
    // Closed risks are read-only: no new or changed forecasts.
    if (e == null || r.isResolved) return;
    final key = '${e.id}|${r.id}';
    final prev = _responses[key];
    final now = DateTime.now();
    _responses[key] = Response(
      expertId: e.id,
      riskId: r.id,
      items: Map.of(items),
      answeredAt: prev?.answeredAt ?? now,
      editedAt: prev == null ? null : now,
      credit: credit ?? prev?.credit,
    );
    // "What is ACAPS missing?" answers become comments for the group.
    for (final entry in items.entries) {
      final id = '${e.id}|${r.id}|${entry.key}';
      final text = entry.value.missing.trim();
      final existing = comments.where((c) => c.id == id).firstOrNull;
      if (text.isEmpty) {
        comments.removeWhere((c) => c.id == id);
      } else if (existing != null) {
        existing.text = text;
      } else {
        comments.add(Comment(id: id, riskId: r.id, itemId: entry.key, authorId: e.id, text: text));
      }
    }
    _skipped[e.id]?.remove(r.id);
    _changed();
  }

  /// Panel members (for this risk) who have answered.
  List<Expert> respondents(Risk r) => panelForRisk(r).where((e) => responseOf(e, r) != null).toList();

  List<ItemAnswer> answersFor(Risk r, String itemId) => [
        for (final e in panelForRisk(r))
          if (responseOf(e, r)?.items[itemId] case final a?) a,
      ];

  /// Simulated history for synthetic experts. Personas never have simulated
  /// answers on active risks, so whoever demos them can take the survey.
  Response? _simulated(Expert e, Risk r) {
    if (!e.simulated || !relevantTo(e, r)) return null;
    if (r.custom) return null; // a brand-new risk has no answers yet
    if (e.persona && r.isActive) return null;
    if (r.id != 'R1043' && Random(stableHash('${e.id}|${r.id}')).nextDouble() > e.participation) return null;

    final base = r.acapsLikelihood ?? 3;
    final items = <String, ItemAnswer>{};
    for (final it in r.surveyItems) {
      final rnd = Random(stableHash('${e.id}|${r.id}|${it.id}'));
      var l = base + const [-2, -1, -1, 0, 0, 0, 0, 1, 1, 2][rnd.nextInt(10)];
      if (it.completion != null && it.completion! <= 15) l -= 1;
      if (r.isResolved && rnd.nextDouble() < e.skill * 0.7) l += r.materialised ? 1 : -1;
      l = l.clamp(1, 5);
      final s = ((r.impact ?? 3) + const [-1, 0, 0, 0, 1][rnd.nextInt(5)]).clamp(1, 5);
      final d = (l - base).abs();
      final agree = d == 0 ? Agreement.yes : (d == 1 ? Agreement.partly : Agreement.no);
      items[it.id] = ItemAnswer(agree: agree, likelihood: l, severity: s);
    }
    final days = r.isResolved ? 190 + stableHash(r.id) % 60 : 1 + stableHash('${e.id}${r.id}') % 3;
    return Response(
      expertId: e.id,
      riskId: r.id,
      items: items,
      answeredAt: DateTime(2026, 11, 6).subtract(Duration(days: days)),
      simulated: true,
    );
  }

  // =========================================================================
  // Scoring & rating
  // =========================================================================

  /// Only likelihood is scored (Brier), against whether the risk materialised.
  ForecastScore? scoreOf(Response resp) {
    final r = byId(resp.riskId);
    if (r == null || !r.isResolved || r.acapsLikelihood == null || resp.items.isEmpty) return null;
    final mine = resp.items.values.map((a) => brier(a.likelihood, r.materialised)).reduce((a, b) => a + b) /
        resp.items.length;
    final acaps = brier(r.acapsLikelihood!, r.materialised);
    return ForecastScore(mine, acaps, Points.forecast(mine));
  }

  List<Comment> commentsBy(Expert e) => comments.where((c) => c.authorId == e.id).toList();

  final _statsCache = <String, ({int points, int resolved, double? brier})>{};

  ({int points, int resolved, double? brier}) statsOf(Expert e) => _statsCache[e.id] ??= _computeStats(e);

  ({int points, int resolved, double? brier}) _computeStats(Expert e) {
    var points = 0, n = 0;
    var sum = 0.0;
    for (final resp in responsesOf(e)) {
      final s = scoreOf(resp);
      if (s == null) continue;
      points += s.points;
      sum += s.mine;
      n++;
    }
    for (final c in commentsBy(e)) {
      if (c.useful) points += Points.usefulComment;
      if (c.usedInRiskId != null) points += Points.usedComment;
    }
    return (points: points, resolved: n, brier: n == 0 ? null : sum / n);
  }

  Set<Award> badgesOf(Expert e) {
    final st = statsOf(e);
    final cs = commentsBy(e);
    final top = _brierRanked().take(3).map((x) => x.id).toSet();
    return {
      if (top.contains(e.id) && st.resolved >= minResolvedForBrier) Award.superEstimator,
      if (cs.any((c) => c.useful)) Award.usefulInsight,
      if (cs.any((c) => c.usedInRiskId != null)) Award.cited,
      if (responsesOf(e).length >= 5) Award.regular,
    };
  }

  List<Expert> _brierRanked() {
    final xs = experts.where((e) => e.onRating && statsOf(e).resolved >= minResolvedForBrier).toList();
    xs.sort((a, b) => statsOf(a).brier!.compareTo(statsOf(b).brier!));
    return xs;
  }

  /// Opt-in rating, ranked by points, with ACAPS's own Brier score as a baseline.
  /// [where] filters experts; [riskWhere] picks the resolved risks the ACAPS
  /// benchmark is scored on (e.g. only risks in the selected country).
  List<RatingRow> rating({bool Function(Expert e)? where, bool Function(Risk r)? riskWhere}) {
    final rows = [
      for (final e in experts.where((e) => e.onRating && (where?.call(e) ?? true)))
        if (statsOf(e) case final s when s.points > 0 || e.id == me?.id)
          RatingRow(expert: e, points: s.points, resolved: s.resolved, brier: s.brier, badges: badgesOf(e)),
    ]..sort((a, b) => b.points.compareTo(a.points));
    final resolved =
        risks.where((r) => r.isResolved && r.acapsLikelihood != null && (riskWhere?.call(r) ?? true)).toList();
    final acaps = resolved.isEmpty
        ? null
        : resolved.fold(0.0, (s, r) => s + brier(r.acapsLikelihood!, r.materialised)) / resolved.length;
    return [...rows, RatingRow(points: 0, resolved: resolved.length, brier: acaps)];
  }

  // =========================================================================
  // Comments
  // =========================================================================

  List<Comment> commentsOn(Risk r) => comments.where((c) => c.riskId == r.id).toList();

  void react(Comment c, bool agree) {
    final e = me;
    if (e == null || c.authorId == e.id) return;
    final on = agree ? c.agreeIds : c.disagreeIds;
    final off = agree ? c.disagreeIds : c.agreeIds;
    off.remove(e.id);
    if (!on.remove(e.id)) on.add(e.id);
    _changed();
  }

  List<Expert> expertsByIds(Iterable<String> ids) => ids.map(expertById).whereType<Expert>().toList();

  // ---- moderator ----

  void toggleUseful(Comment c) {
    c.useful = !c.useful;
    c.usefulBy = c.useful ? sessionModeratorId : null;
    _markReviewed(c);
    _changed();
  }

  void setUsedIn(Comment c, String? riskId) {
    c.usedInRiskId = riskId;
    c.usedBy = riskId == null ? null : sessionModeratorId;
    _markReviewed(c);
    _changed();
  }

  void setReviewed(Comment c, bool v) {
    c.reviewed = v;
    c.reviewedBy = v ? sessionModeratorId : null;
    _changed();
  }

  void _markReviewed(Comment c) {
    if (!c.reviewed) c.reviewedBy = sessionModeratorId;
    c.reviewed = true;
  }

  /// What one moderator has done, for their profile.
  ({int reviewed, int useful, int used}) activityOf(Moderator m) => (
        reviewed: comments.where((c) => c.reviewedBy == m.id).length,
        useful: comments.where((c) => c.usefulBy == m.id).length,
        used: comments.where((c) => c.usedBy == m.id).length,
      );

  /// New comments no moderator has handled yet. This is the only number on
  /// the moderator's Inbox badge.
  int get commentsToReview => comments.where((c) => c.needsReview).length;

  /// Moderator view of one risk: response rate, comments, and how far the
  /// experts' likelihood sits from the ACAPS rating.
  RiskModStats modStats(Risk r) {
    final panel = panelForRisk(r);
    final answered = respondents(r);
    final all = [for (final it in r.surveyItems) ...answersFor(r, it.id)];
    final cs = commentsOn(r);
    final mean = all.isEmpty ? null : all.fold(0, (s, a) => s + a.likelihood) / all.length;
    final disagree = all.isEmpty
        ? 0.0
        : all.fold(0.0, (s, a) => s + (a.agree == Agreement.no ? 1 : (a.agree == Agreement.partly ? 0.5 : 0))) / all.length;
    return RiskModStats(
      panel: panel.length,
      answered: answered.length,
      comments: cs.length,
      toReview: cs.where((c) => c.needsReview).length,
      expertLikelihood: mean,
      acapsLikelihood: r.acapsLikelihood,
      disagreement: disagree,
    );
  }

  /// Panel health for one country.
  PanelStats panelStats(String country) {
    final experts = panelFor(country);
    final active = risks.where((r) => r.isActive && riskCountries(r).contains(country)).toList();
    // Share of this country's own panel that answered, averaged over its active risks.
    var rate = 0.0;
    for (final r in active) {
      rate += experts.where((e) => responseOf(e, r) != null).length / (experts.isEmpty ? 1 : experts.length);
    }
    return PanelStats(
      country: country,
      region: regionOf(country),
      experts: experts,
      activeRisks: active.length,
      responseRate: active.isEmpty || experts.isEmpty ? null : rate / active.length,
    );
  }

  /// Countries with active risks whose panel is too small to stay anonymous.
  List<({String country, int n, int active})> get thinPanels {
    final out = <({String country, int n, int active})>[];
    for (final c in countries) {
      final active = risks.where((r) => r.isActive && riskCountries(r).contains(c)).length;
      if (active == 0) continue;
      final n = panelFor(c).length;
      if (n < minPanel) out.add((country: c, n: n, active: active));
    }
    out.sort((a, b) => b.n != a.n ? b.n.compareTo(a.n) : b.active.compareTo(a.active));
    return out;
  }

  // =========================================================================
  // Risks created by the moderator
  // =========================================================================

  /// Next free id after the highest "R<number>" in use.
  String nextRiskId() {
    final n = risks.map((r) => int.tryParse(r.id.replaceAll(RegExp('[^0-9]'), '')) ?? 0).fold(0, max);
    return 'R${n + 1}';
  }

  /// Adds a new risk, or replaces the one with the same id.
  void saveRisk(Risk r) {
    final i = risks.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      risks[i] = r;
    } else {
      risks.add(r);
    }
    _changed();
  }

  /// Only risks created in the app can be deleted; Risk Radar risks stay.
  void deleteRisk(Risk r) {
    if (!r.custom) return;
    risks.removeWhere((x) => x.id == r.id);
    comments.removeWhere((c) => c.riskId == r.id);
    _responses.removeWhere((_, v) => v.riskId == r.id);
    for (final s in _skipped.values) {
      s.remove(r.id);
    }
    _changed();
  }

  // =========================================================================
  // Public view: aggregates only, safe to publish
  // =========================================================================

  /// Contributors who agreed to be named for this risk (their choice in the
  /// survey, or their profile default), sorted by name.
  List<({String name, Credit as})> creditsFor(Risk r) => [
        for (final e in respondents(r))
          if (publicCredit(e, responseOf(e, r)?.credit) case final c?) c,
      ]..sort((a, b) => a.name.compareTo(b.name));

  /// What the public may see for one risk: aggregates only, no comments, no
  /// respondent countries; no results at all below [minPanel] respondents.
  /// With [credits], experts who agreed are listed as contributors (never
  /// next to an answer).
  Map<String, dynamic> publicView(Risk r, {bool credits = false}) {
    final n = respondents(r).length;
    List<int> dist(Iterable<int> xs) {
      final c = List.filled(5, 0);
      for (final x in xs) {
        c[x - 1]++;
      }
      return c;
    }

    double? mean(List<int> xs) => xs.isEmpty ? null : double.parse((xs.reduce((a, b) => a + b) / xs.length).toStringAsFixed(2));
    return {
      'risk_id': r.id,
      'title': r.title,
      'countries': riskCountries(r),
      'status': r.status,
      'acaps': {
        'probability': r.probabilityIdx == null ? null : levelLabels[r.probabilityIdx!],
        'likelihood_1_5': r.acapsLikelihood,
        'impact_1_5': r.impact,
        'risk_level': r.level.isEmpty ? null : r.level,
      },
      'respondents': n,
      'published': n >= minPanel,
      if (n >= minPanel)
        'questions': [
          for (final it in r.surveyItems)
            () {
              final a = answersFor(r, it.id);
              final l = [for (final x in a) x.likelihood], s = [for (final x in a) x.severity];
              return {
                'id': it.id,
                'title': it.title,
                'answers': a.length,
                'agreement_with_acaps': {for (final g in Agreement.values) g.name: a.where((x) => x.agree == g).length},
                'likelihood': {'distribution_1_5': dist(l), 'mean': mean(l)},
                'severity': {'distribution_1_5': dist(s), 'mean': mean(s)},
              };
            }(),
        ],
      if (n >= minPanel && credits) ...() {
        final cs = creditsFor(r);
        return {
          'contributors': [
            for (final c in cs) {'name': c.name, 'credited_as': c.as == Credit.realName ? 'real_name' : 'pseudonym'},
          ],
          'anonymous_contributors': n - cs.length,
        };
      }(),
    };
  }

  /// A file ready to publish: one risk, or every risk with enough respondents.
  String publicViewJson(Iterable<Risk> rs, {bool credits = false}) => const JsonEncoder.withIndent('  ').convert({
        'schema': 'acaps-ground-truth/public-view/v1',
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'min_respondents': minPanel,
        'risks': [for (final r in rs) publicView(r, credits: credits)],
      });

  /// Risks whose public view would show results.
  List<Risk> get publishableRisks =>
      risks.where((r) => (r.isActive || r.isResolved) && respondents(r).length >= minPanel).toList();

  /// Raw stored expert records, exactly as persisted (for the demo).
  String get rawExpertTable =>
      const JsonEncoder.withIndent('  ').convert([for (final e in experts) e.toJson()]);

  // =========================================================================
  // Seed data (synthetic: no real experts)
  // =========================================================================

  void _seed() {
    experts = [
      // Personas you can log in as.
      Expert(id: 'p1', realName: 'Amina Haroun', pseudonym: 'Harmattan-17', level: Anonymity.knownToAcaps,
          homeCountry: 'Chad', interests: {'Sudan', 'Cameroon'}, simulated: true, persona: true,
          participation: 0.85, skill: 0.8),
      Expert(id: 'p2', realName: 'Jean-Paul Ndoumbé', pseudonym: 'Kestrel-42', level: Anonymity.pseudonymous,
          homeCountry: 'Cameroon', interests: {'Chad', 'Central African Republic'}, simulated: true, persona: true,
          participation: 0.9, skill: 0.5),
      Expert(id: 'p3', realName: null, pseudonym: 'Sirocco-08', level: Anonymity.anonymous,
          homeCountry: 'Chad', interests: {'Sudan', 'Mali'}, simulated: true, persona: true,
          onRating: false, participation: 0.8, skill: 0.35),
      // Chad panel.
      Expert(id: 'e4', realName: 'Fatimé Abakar', pseudonym: 'Baobab-23', level: Anonymity.knownToAcaps,
          homeCountry: 'Chad', interests: {'Sudan'}, simulated: true, participation: 0.9, skill: 0.9),
      Expert(id: 'e5', realName: 'Moussa Idriss', pseudonym: 'Lantern-61', level: Anonymity.pseudonymous,
          homeCountry: 'Chad', simulated: true, participation: 0.8, skill: 0.4),
      Expert(id: 'e6', realName: null, pseudonym: 'Delta-30', level: Anonymity.anonymous,
          homeCountry: 'Sudan', interests: {'Chad'}, simulated: true, participation: 0.75, skill: 0.6),
      Expert(id: 'e7', realName: 'Halima Osman', pseudonym: 'Nomad-55', level: Anonymity.pseudonymous,
          homeCountry: 'Sudan', interests: {'Chad', 'South Sudan'}, simulated: true, participation: 0.85, skill: 0.7),
      Expert(id: 'e8', realName: 'Mahamat Saleh', pseudonym: 'Meridian-12', level: Anonymity.knownToAcaps,
          homeCountry: 'Chad', interests: {'Niger'}, simulated: true, onRating: false, participation: 0.7, skill: 0.2),
      // Other panels.
      Expert(id: 'e9', realName: 'Omar Bashir', pseudonym: 'Atlas-77', level: Anonymity.pseudonymous,
          homeCountry: 'Sudan', interests: {'South Sudan'}, simulated: true, participation: 0.8, skill: 0.55),
      Expert(id: 'e10', realName: null, pseudonym: 'Monsoon-04', level: Anonymity.anonymous,
          homeCountry: 'South Sudan', simulated: true, participation: 0.7, skill: 0.45),
      Expert(id: 'e11', realName: 'Wanjiru Kamau', pseudonym: 'Compass-19', level: Anonymity.knownToAcaps,
          homeCountry: 'Kenya', interests: {'Sudan', 'Ethiopia'}, simulated: true, participation: 0.9, skill: 0.75),
      Expert(id: 'e12', realName: 'Aïssata Traoré', pseudonym: 'Cedar-66', level: Anonymity.pseudonymous,
          homeCountry: 'Mali', interests: {'Niger'}, simulated: true, participation: 0.8, skill: 0.6),
    ];
    _responses.clear();
    _skipped.clear();
    final t1 = 'R1043 - T0618', t2 = 'R1043 - T0619', t3 = 'R1043 - T0620';
    comments = [
      Comment(id: 's1', riskId: 'R1043', itemId: t1, authorId: 'e6',
          text: 'Smuggling routes are shifting north. Watch Bahaï and Tiné, not only Adré.',
          agreeIds: {'e4', 'e5', 'e8'}),
      Comment(id: 's2', riskId: 'R1043', itemId: t1, authorId: 'e4',
          text: 'The rainy season (Jul-Sep) usually slows cross-border movement. Expect a dip before escalation picks up again.',
          agreeIds: {'e6', 'e7'}, disagreeIds: {'e5', 'e8'}),
      Comment(id: 's3', riskId: 'R1043', itemId: t2, authorId: 'e7',
          text: 'Threats against Amdjarass are mostly rhetoric so far. Attacks on fuel convoys on the Abéché road are the more likely strike.',
          agreeIds: {'e4', 'e5', 'e6', 'e8'}, useful: true, usefulBy: 'm2', reviewed: true, reviewedBy: 'm2'),
      Comment(id: 's4', riskId: 'R1043', itemId: t3, authorId: 'e5',
          text: 'Recruitment in the Ouaddaï camps is an earlier signal of proxy mobilisation than armed incursions.',
          agreeIds: {'e4', 'e6', 'e7'}, disagreeIds: {'e8'}, usedInRiskId: 'R1048', usedBy: 'm1', reviewed: true, reviewedBy: 'm1'),
      // A few more, so the moderator filters have something to show.
      Comment(id: 's6', riskId: 'R1048', itemId: byId('R1048')?.surveyItems.first.id ?? 'risk', authorId: 'e9',
          text: 'RSF supply lines into Blue Nile run through Ethiopian border markets. Watch Kurmuk.',
          agreeIds: {'e7', 'e11'}, disagreeIds: {'e4'}),
      Comment(id: 's7', riskId: 'R1048', itemId: byId('R1048')?.surveyItems.last.id ?? 'risk', authorId: 'e11',
          text: 'Displacement figures here are probably undercounted: many people move to Ethiopia and are not registered.',
          agreeIds: {'e9', 'e6', 'e7', 'p1'}),
      Comment(id: 's8', riskId: 'R1037', itemId: byId('R1037')?.surveyItems.first.id ?? 'risk', authorId: 'e10',
          text: 'Flooding in Jonglei will cut road access before the fighting does.',
          agreeIds: {'e9'}, disagreeIds: {'e7'}),
      Comment(id: 's9', riskId: 'R1043', itemId: 'R1043 - T0620', authorId: 'e8',
          text: 'I see little sign of proxy mobilisation yet; this trigger looks overrated.',
          agreeIds: {}, disagreeIds: {'e4', 'e5', 'e6'}, reviewed: true, reviewedBy: 'm3'),
      // Persona history: shows moderator feedback under Profile -> My forecasts.
      Comment(id: 's5', riskId: 'R0002', itemId: byId('R0002')?.surveyItems.first.id ?? 'risk', authorId: 'p1',
          text: 'Fighting is pushing traders off the El Geneina - Adre route; watch fuel prices in Adre market.',
          agreeIds: {'e4', 'e6', 'e7', 'e9'}, disagreeIds: {'e11'}, useful: true, usefulBy: 'm1', usedInRiskId: 'R1043', usedBy: 'm1',
          reviewed: true, reviewedBy: 'm1'),
    ];
  }

  // =========================================================================
  // Persistence
  // =========================================================================

  static const _prefsKey = 'ground_truth_db_v4';

  void _changed() {
    _statsCache.clear();
    notifyListeners();
    _save();
  }

  void _save() {
    _prefs?.setString(
      _prefsKey,
      jsonEncode({
        'experts': [for (final e in experts) e.toJson()],
        'responses': [for (final r in _responses.values) r.toJson()],
        'comments': [for (final c in comments) c.toJson()],
        'custom_risks': [for (final r in risks.where((r) => r.custom)) r.toJson()],
        'skipped': {for (final e in _skipped.entries) e.key: e.value.toList()},
        'invite': invitePanel,
        'session': sessionExpertId,
        'moderator': sessionModeratorId,
      }),
    );
  }

  bool _restore() {
    try {
      final raw = _prefs?.getString(_prefsKey);
      if (raw == null) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      experts = [for (final e in m['experts'] as List) Expert.fromJson((e as Map).cast<String, dynamic>())];
      _responses.clear();
      for (final r in m['responses'] as List) {
        final resp = Response.fromJson((r as Map).cast<String, dynamic>());
        // Old "practice" answers on closed risks: no longer allowed, never scored.
        if (byId(resp.riskId)?.isResolved ?? false) continue;
        _responses['${resp.expertId}|${resp.riskId}'] = resp;
      }
      comments = [for (final c in m['comments'] as List) Comment.fromJson((c as Map).cast<String, dynamic>())];
      _skipped
        ..clear()
        ..addAll({
          for (final e in ((m['skipped'] as Map?) ?? const {}).entries)
            e.key as String: {...(e.value as List).cast<String>()},
        });
      invitePanel = m['invite'] as String?;
      sessionExpertId = m['session'] as String?;
      final mod = m['moderator'];
      sessionModeratorId = mod == true ? moderators.first.id : moderatorById(mod is String ? mod : null)?.id;
      risks
        ..removeWhere((r) => r.custom)
        ..addAll([for (final r in (m['custom_risks'] as List? ?? const [])) Risk.fromJson((r as Map).cast<String, dynamic>())]);
      return true;
    } catch (_) {
      return false; // corrupt or old state: start fresh
    }
  }
}

final appState = AppState();
