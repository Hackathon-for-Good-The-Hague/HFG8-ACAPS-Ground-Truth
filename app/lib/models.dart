/// ACAPS 5-point probability scale, mapped to numeric probabilities for scoring.
const levelLabels = ['Very low', 'Low', 'Medium', 'High', 'Very high'];
const levelProbs = [0.1, 0.3, 0.5, 0.7, 0.9];

int? parseLevel5(String s) {
  switch (s.trim().toLowerCase()) {
    case 'very low':
      return 0;
    case 'low':
      return 1;
    case 'medium':
      return 2;
    case 'high':
      return 3;
    case 'very high':
      return 4;
  }
  return null;
}

/// "[ACLED 08/04/2026](https://...)" -> "ACLED 08/04/2026"
String stripMarkdownLinks(String s) => s
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(r'\)', ')')
    .trim();

class Trigger {
  final String id;
  final String title;
  final String description;
  final int? completion;

  const Trigger({
    required this.id,
    required this.title,
    required this.description,
    this.completion,
  });
}

/// Parses the structured "Trigger ID: / Title: / Description:" field.
List<Trigger> parseTriggers(String raw) {
  if (!raw.contains('Trigger ID:')) return const [];
  final out = <Trigger>[];
  for (final chunk in raw.split('Trigger ID:').skip(1)) {
    final id = chunk.split('\n').first.trim();
    final title =
        RegExp(r'Title:[ \t]*(.*)').firstMatch(chunk)?.group(1)?.trim() ?? '';
    var desc = RegExp(
                r'Description:\s*([\s\S]*?)(?:\n\s*Sources:|\n\s*Completion rate:|$)')
            .firstMatch(chunk)
            ?.group(1) ??
        '';
    desc = desc.trim();
    while (desc.startsWith(':')) {
      desc = desc.substring(1).trim();
    }
    final completion =
        RegExp(r'Completion rate:\s*(\d+)%').firstMatch(chunk)?.group(1);
    out.add(Trigger(
      id: id,
      title: title.isEmpty ? id : title,
      description: stripMarkdownLinks(desc),
      completion: completion == null ? null : int.parse(completion),
    ));
  }
  return out;
}

class Risk {
  final String id;
  final String title;
  final String type;
  final String country;
  final String rationale;
  final int? probabilityIdx;
  final int? impact;
  final String level;
  final String trend;
  final String status;
  final String exposure;
  final String needs;
  final String materialisation;
  final List<Trigger> triggers;

  /// Created by an ACAPS moderator in the app (not from the Risk Radar export).
  final bool custom;

  const Risk({
    this.custom = false,
    required this.id,
    required this.title,
    required this.type,
    required this.country,
    required this.rationale,
    required this.probabilityIdx,
    required this.impact,
    required this.level,
    required this.trend,
    required this.status,
    required this.exposure,
    required this.needs,
    required this.materialisation,
    required this.triggers,
  });

  factory Risk.fromRow(Map<String, String> m) {
    String f(String k) => (m[k] ?? '').trim();
    final mat = [f('Hazard materialisation'), f('Impact materialisation description')]
        .where((s) => s.isNotEmpty)
        .join('\n\n');
    return Risk(
      id: f('Risk ID'),
      title: f('Risk Title'),
      type: f('Risk Type'),
      country: f('Country'),
      rationale: stripMarkdownLinks(f('Rationale')),
      probabilityIdx: parseLevel5(f('Probability')),
      impact: int.tryParse(f('Impact')),
      level: f('Risk Level'),
      trend: f('Risk trend'),
      status: f('Status'),
      exposure: f('Expected exposure'),
      needs: f('Expected priority needs'),
      materialisation: stripMarkdownLinks(mat),
      triggers: parseTriggers(m['Triggers'] ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'country': country,
        'rationale': rationale,
        'probability': probabilityIdx,
        'impact': impact,
        'level': level,
        'trend': trend,
        'status': status,
        'exposure': exposure,
        'needs': needs,
        'materialisation': materialisation,
        'triggers': [
          for (final t in triggers) {'id': t.id, 'title': t.title, 'description': t.description},
        ],
      };

  factory Risk.fromJson(Map<String, dynamic> m) => Risk(
        custom: true,
        id: m['id'] as String,
        title: m['title'] as String,
        type: (m['type'] as String?) ?? '',
        country: m['country'] as String,
        rationale: (m['rationale'] as String?) ?? '',
        probabilityIdx: (m['probability'] as num?)?.toInt(),
        impact: (m['impact'] as num?)?.toInt(),
        level: (m['level'] as String?) ?? '',
        trend: (m['trend'] as String?) ?? '',
        status: (m['status'] as String?) ?? 'Active',
        exposure: (m['exposure'] as String?) ?? '',
        needs: (m['needs'] as String?) ?? '',
        materialisation: (m['materialisation'] as String?) ?? '',
        triggers: [
          for (final t in (m['triggers'] as List? ?? const []))
            Trigger(id: t['id'] as String, title: t['title'] as String, description: (t['description'] as String?) ?? ''),
        ],
      );

  bool get isActive => status.toLowerCase() == 'active';
  bool get materialised => status.toLowerCase() == 'materialised';
  bool get isResolved =>
      materialised || status.toLowerCase() == 'not materialised';

  bool inCountry(String c) =>
      country.split(',').map((s) => s.trim()).contains(c);

  String get shortType {
    final t = type.toLowerCase();
    if (t.startsWith('new')) return 'New risk';
    if (t.startsWith('marked')) return 'Deterioration';
    if (t.startsWith('future')) return 'Hazard impact';
    return type.isEmpty ? 'Risk' : type;
  }

  /// First paragraph of the rationale, trimmed for a card.
  String get summary {
    final p = rationale.split(RegExp(r'\n\s*\n')).first.trim();
    return p.length > 320 ? '${p.substring(0, 320).trimRight()}…' : p;
  }
}

/// Hand-written one-line summaries for demo risks; others fall back to the title.
const _oneLiners = {
  'R1043': 'The war in Sudan may spill across the border into eastern Chad.',
};

extension RiskSurvey on Risk {
  String get oneLiner => _oneLiners[id] ?? title;

  /// One survey screen per trigger (max 3), or one screen for the risk itself.
  List<SurveyItem> get surveyItems => triggers.isEmpty
      ? [SurveyItem(id: 'risk', title: 'The risk as a whole', description: summary)]
      : [
          for (final t in triggers.take(3))
            SurveyItem(id: t.id, title: t.title, description: t.description, completion: t.completion),
        ];

  /// ACAPS likelihood on the 1-5 survey scale.
  int? get acapsLikelihood => probabilityIdx == null ? null : probabilityIdx! + 1;
}

class SurveyItem {
  final String id;
  final String title;
  final String description;
  final int? completion;

  const SurveyItem({required this.id, required this.title, required this.description, this.completion});
}

enum Agreement { yes, partly, no }

extension AgreementText on Agreement {
  String get label => switch (this) {
        Agreement.yes => 'Yes',
        Agreement.partly => 'Partly',
        Agreement.no => 'No',
      };
}

const likelihoodLabels = ['Very unlikely', 'Unlikely', 'Even chance', 'Likely', 'Very likely'];
const severityLabels = ['Minor', 'Moderate', 'Serious', 'Severe', 'Critical'];

/// Answers on one trigger screen.
class ItemAnswer {
  final Agreement agree;

  /// 1..5
  final int likelihood;

  /// 1..5
  final int severity;
  final String missing;

  const ItemAnswer({required this.agree, required this.likelihood, required this.severity, this.missing = ''});

  Map<String, dynamic> toJson() =>
      {'agree': agree.index, 'likelihood': likelihood, 'severity': severity, 'missing': missing};

  factory ItemAnswer.fromJson(Map<String, dynamic> m) => ItemAnswer(
        agree: Agreement.values[(m['agree'] as num).toInt()],
        likelihood: (m['likelihood'] as num).toInt(),
        severity: (m['severity'] as num).toInt(),
        missing: (m['missing'] as String?) ?? '',
      );
}

/// How an expert wants to be credited when ACAPS publishes a risk they
/// answered. Credits list contributors; they never sit next to an answer.
enum Credit { realName, pseudonym, anonymous }

extension CreditText on Credit {
  String get label => switch (this) {
        Credit.realName => 'Real name',
        Credit.pseudonym => 'Pseudonym',
        Credit.anonymous => 'Anonymous',
      };
}

/// One expert's answers to one risk survey.
class Response {
  final String expertId;
  final String riskId;
  final Map<String, ItemAnswer> items;
  final DateTime answeredAt;
  final DateTime? editedAt;
  final bool simulated;

  /// Chosen for this risk; null = the default from the expert's profile.
  final Credit? credit;

  const Response({
    required this.expertId,
    required this.riskId,
    required this.items,
    required this.answeredAt,
    this.editedAt,
    this.simulated = false,
    this.credit,
  });

  Map<String, dynamic> toJson() => {
        'expert': expertId,
        'risk': riskId,
        'items': {for (final e in items.entries) e.key: e.value.toJson()},
        'at': answeredAt.toIso8601String(),
        if (editedAt != null) 'edited': editedAt!.toIso8601String(),
        if (credit != null) 'credit': credit!.name,
      };

  factory Response.fromJson(Map<String, dynamic> m) => Response(
        expertId: m['expert'] as String,
        riskId: m['risk'] as String,
        items: {
          for (final e in (m['items'] as Map).entries)
            e.key as String: ItemAnswer.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        answeredAt: DateTime.parse(m['at'] as String),
        editedAt: m['edited'] == null ? null : DateTime.parse(m['edited'] as String),
        credit: Credit.values.where((c) => c.name == m['credit']).firstOrNull,
      );
}

/// A "what is ACAPS missing?" contribution.
class Comment {
  final String id;
  final String riskId;
  final String itemId;
  final String authorId;
  String text;
  bool useful;
  String? usedInRiskId;

  /// A moderator has looked at it (marking useful / used also counts).
  bool reviewed;
  final Set<String> agreeIds;
  final Set<String> disagreeIds;

  Comment({
    required this.id,
    required this.riskId,
    required this.itemId,
    required this.authorId,
    required this.text,
    this.useful = false,
    this.usedInRiskId,
    this.reviewed = false,
    Set<String>? agreeIds,
    Set<String>? disagreeIds,
  })  : agreeIds = agreeIds ?? {},
        disagreeIds = disagreeIds ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'risk': riskId,
        'item': itemId,
        'author': authorId,
        'text': text,
        'useful': useful,
        'used_in': usedInRiskId,
        'reviewed': reviewed,
        'agree': agreeIds.toList(),
        'disagree': disagreeIds.toList(),
      };

  bool get needsReview => !reviewed && !useful && usedInRiskId == null;

  factory Comment.fromJson(Map<String, dynamic> m) => Comment(
        id: m['id'] as String,
        riskId: m['risk'] as String,
        itemId: m['item'] as String,
        authorId: m['author'] as String,
        text: m['text'] as String,
        useful: m['useful'] == true,
        usedInRiskId: m['used_in'] as String?,
        reviewed: m['reviewed'] == true,
        agreeIds: {...((m['agree'] as List?) ?? const []).cast<String>()},
        disagreeIds: {...((m['disagree'] as List?) ?? const []).cast<String>()},
      );
}
