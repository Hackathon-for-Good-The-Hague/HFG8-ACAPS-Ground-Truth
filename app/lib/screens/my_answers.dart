import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'survey.dart';

enum _Filter { all, open, matured }

/// History of my answers: risk status and what happened to my comments.
class MyAnswersScreen extends StatefulWidget {
  const MyAnswersScreen({super.key});

  @override
  State<MyAnswersScreen> createState() => _MyAnswersScreenState();
}

class _MyAnswersScreenState extends State<MyAnswersScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My forecasts')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final me = appState.me;
          if (me == null) return const SizedBox();
          final responses = {for (final r in appState.responsesOf(me)) r.riskId: r};
          final myComments = appState.commentsBy(me);
          final riskIds = {...responses.keys, ...myComments.map((c) => c.riskId)};
          final entries = [
            for (final id in riskIds)
              if (appState.byId(id) case final r?) (risk: r, response: responses[id], comments: myComments.where((c) => c.riskId == id).toList()),
          ]..sort((a, b) {
              final da = a.response?.editedAt ?? a.response?.answeredAt ?? DateTime(2000);
              final db = b.response?.editedAt ?? b.response?.answeredAt ?? DateTime(2000);
              return db.compareTo(da);
            });
          final shown = entries.where((e) => switch (_filter) {
                _Filter.all => true,
                _Filter.open => e.risk.isActive,
                _Filter.matured => e.risk.isResolved,
              });

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      _Count('${responses.length}', 'forecasts'),
                      _Count('${myComments.length}', 'comments'),
                      _Count('${myComments.where((c) => c.useful).length}', 'marked useful'),
                      _Count('${myComments.where((c) => c.usedInRiskId != null).length}', 'used in analysis'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in _Filter.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.all => 'All',
                        _Filter.open => 'In progress',
                        _Filter.matured => 'Matured',
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text('Nothing here yet. Answer a risk from the Risks tab.', style: t.bodyMedium, textAlign: TextAlign.center),
                ),
              for (final e in shown) _AnswerCard(risk: e.risk, response: e.response, comments: e.comments),
            ],
          );
        },
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final Risk risk;
  final Response? response;
  final List<Comment> comments;
  const _AnswerCard({required this.risk, required this.response, required this.comments});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final resp = response;
    final score = resp == null ? null : appState.scoreOf(resp);
    final items = risk.surveyItems;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: resp == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SurveyScreen(risk: risk, start: SurveyStart.summary))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${risk.id} · ${risk.country}',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
                    ),
                    _StatusChip(risk: risk, response: resp),
                  ],
                ),
                const SizedBox(height: 6),
                Text(risk.oneLiner, style: t.titleSmall),
                if (resp != null) ...[
                  const SizedBox(height: 4),
                  Text('${resp.editedAt == null ? 'Answered' : 'Edited'} ${formatDate(resp.editedAt ?? resp.answeredAt)}', style: t.bodySmall),
                  const SizedBox(height: 8),
                  for (final it in items)
                    if (resp.items[it.id] case final a?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${items.length > 1 ? '${it.title}: ' : ''}agree ${a.agree.label.toLowerCase()} · likely ${a.likelihood}/5 · bad ${a.severity}/5',
                          style: t.bodySmall,
                        ),
                      ),
                ],
                if (score != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.track_changes, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Accuracy ${accuracyPct(score.mine)}% (ACAPS ${accuracyPct(score.acaps)}%) · +${score.points} points',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
                for (final c in comments) _MyComment(comment: c, items: items),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Risk risk;
  final Response? response;
  const _StatusChip({required this.risk, required this.response});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = risk.isActive
        ? (
            response == null ? 'In progress' : 'In progress · matures ${formatDate(response!.answeredAt.add(const Duration(days: 182)))}',
            Icons.hourglass_top,
            AppColors.low,
          )
        : risk.materialised
            ? ('Happened', Icons.warning_amber_rounded, AppColors.high)
            : ('Did not happen', Icons.shield_outlined, scaleColors[1]);
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withAlpha(140))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyComment extends StatelessWidget {
  final Comment comment;
  final List<SurveyItem> items;
  const _MyComment({required this.comment, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = comment;
    final item = items.where((i) => i.id == c.itemId).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withAlpha(150), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item != null && items.length > 1 ? 'Your comment on: ${item.title}' : 'Your comment',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(c.text, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Flag(
                on: c.useful,
                icon: Icons.lightbulb_outline,
                // Experts never see which moderator did it: always "ACAPS".
                onText: 'Marked useful by ACAPS · +${Points.usefulComment}',
                offText: 'Not marked useful yet',
              ),
              _Flag(
                on: c.usedInRiskId != null,
                icon: Icons.push_pin_outlined,
                onText: 'Used in analysis of ${c.usedInRiskId} · +${Points.usedComment}',
                offText: 'Not used in another analysis yet',
              ),
              Pill('Agree ${c.agreeIds.length} · Disagree ${c.disagreeIds.length}', icon: Icons.thumbs_up_down_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  final bool on;
  final IconData icon;
  final String onText;
  final String offText;
  const _Flag({required this.on, required this.icon, required this.onText, required this.offText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = on ? cs.primary : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: on ? cs.primary.withAlpha(30) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? cs.primary : cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(on ? Icons.check_circle : icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(on ? onText : offText, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color))),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final String value;
  final String label;
  const _Count(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
