import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

enum SurveyStart { intro, questions, summary }

/// "Not now" on a risk: skip it and say so clearly, with Undo. The risk stays
/// in the Risks list (tagged "Skipped") and the banner hides for this session.
void notNow(BuildContext context, Risk r) {
  appState.skip(r);
  final title = r.title.length > 90 ? '${r.title.substring(0, 90).trimRight()}…' : r.title;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      // A snack bar with an action stays until closed unless told otherwise.
      persist: false,
      duration: const Duration(seconds: 5),
      content: Text('Skipped: "$title". It stays in your list, marked "Skipped", so you can answer later.'),
      action: SnackBarAction(label: 'Undo', onPressed: () => appState.undoSkip(r)),
    ));
}

class _Draft {
  Agreement? agree;
  int? likelihood;
  int? severity;
  final TextEditingController missing;

  _Draft([ItemAnswer? a])
      : agree = a?.agree,
        likelihood = a?.likelihood,
        severity = a?.severity,
        missing = TextEditingController(text: a?.missing ?? '');

  bool get complete => agree != null && likelihood != null && severity != null;

  ItemAnswer toAnswer() =>
      ItemAnswer(agree: agree!, likelihood: likelihood!, severity: severity!, missing: missing.text.trim());
}

/// Risk survey: intro -> one screen per trigger -> thank you + group summary.
class SurveyScreen extends StatefulWidget {
  final Risk risk;
  final SurveyStart start;

  /// Opened by a notification or the "new risk" pop-up on app entry.
  final bool fromNotification;
  const SurveyScreen({super.key, required this.risk, this.start = SurveyStart.intro, this.fromNotification = false});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  late final List<SurveyItem> items = widget.risk.surveyItems;
  late final Map<String, _Draft> drafts;
  late int step; // 0 = intro, 1..n = items, n+1 = summary
  bool _details = false;

  /// How to credit me if this risk is published; starts from my profile.
  Credit? _credit;

  Risk get r => widget.risk;
  int get summaryStep => items.length + 1;

  @override
  void initState() {
    super.initState();
    final me = appState.me;
    final existing = me == null ? null : appState.responseOf(me, r);
    drafts = {for (final it in items) it.id: _Draft(existing?.items[it.id])};
    _credit = me == null ? null : (existing?.credit ?? defaultCredit(me));
    step = switch (widget.start) {
      // Closed risks are read-only: straight to what happened and the group view.
      _ when me == null || r.isResolved => summaryStep,
      SurveyStart.intro => 0,
      SurveyStart.questions => 1,
      SurveyStart.summary => existing == null ? 0 : summaryStep,
    };
  }

  @override
  void dispose() {
    for (final d in drafts.values) {
      d.missing.dispose();
    }
    super.dispose();
  }

  void _go(int s) {
    FocusScope.of(context).unfocus();
    if (s == summaryStep) {
      appState.submit(r, {for (final e in drafts.entries) e.key: e.value.toAnswer()}, credit: _credit);
    }
    setState(() => step = s);
  }

  @override
  Widget build(BuildContext context) {
    final inItems = step >= 1 && step <= items.length;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(
            step == 0
                ? r.id
                : (inItems
                    ? '${r.id} · ${items.length == 1 ? 'Question' : 'Trigger'} $step of ${items.length}'
                    : (r.isResolved ? '${r.id} · What happened' : 'Group summary')),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          bottom: inItems
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: step / items.length, minHeight: 4),
                )
              : null,
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(step),
            child: step == 0
                ? _intro(context)
                : inItems
                    ? _ItemPage(
                        item: items[step - 1],
                        index: step - 1,
                        total: items.length,
                        draft: drafts[items[step - 1].id]!,
                        onChanged: () => setState(() {}),
                        footer: step == items.length && appState.me != null && _credit != null
                            ? CreditPicker(expert: appState.me!, value: _credit!, onChanged: (c) => setState(() => _credit = c))
                            : null,
                      )
                    : _Summary(risk: r),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: _buttons(context),
          ),
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    final me = appState.me;
    if (step == 0) {
      return Row(
        children: [
          if (r.isActive && me != null) ...[
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: () {
                notNow(context, r);
                Navigator.of(context).pop();
              },
              child: const Text('Not now'),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton.icon(onPressed: () => _go(1), icon: const Icon(Icons.play_arrow), label: const Text('Start')),
          ),
        ],
      );
    }
    if (step <= items.length) {
      final d = drafts[items[step - 1].id]!;
      final last = step == items.length;
      return Row(
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
            onPressed: () => _go(step - 1),
            child: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: d.complete ? () => _go(step + 1) : null,
              child: Text(last ? 'Send answers' : 'Next'),
            ),
          ),
        ],
      );
    }
    final locked = r.isResolved || me == null;
    return Row(
      children: [
        if (!locked) ...[
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => setState(() => step = 1),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Change answer'),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ),
      ],
    );
  }

  Widget _intro(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (widget.fromNotification && r.isActive) ...[
          InfoBanner(
            icon: Icons.notifications_active_outlined,
            color: Theme.of(context).colorScheme.primary,
            text: 'ACAPS updated this risk in ${AppState.riskCountries(r).join(', ')}. Got 2 minutes?',
          ),
          const SizedBox(height: 12),
        ],
        RiskHeader(risk: r),
        const SizedBox(height: 16),
        Text(
          '${items.length} short ${items.length == 1 ? 'screen' : 'screens'}, about 2 minutes. '
          'You answer before you see the group, so your view stays independent.',
          style: t.bodyMedium,
        ),
        // Always visible: exposure and triggers.
        if (r.exposure.isNotEmpty) ...[
          const SectionLabel('Expected exposure'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.groups_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(r.exposure, style: t.bodyMedium)),
            ],
          ),
        ],
        if (r.triggers.isNotEmpty) ...[
          const SectionLabel('Triggers ACAPS is watching'),
          for (final tr in r.triggers.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr.title)),
                  if (tr.completion != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: LinearProgressIndicator(
                        value: tr.completion! / 100,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        color: Color.lerp(scaleColors[1], scaleColors[4], tr.completion! / 100),
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${tr.completion}%', style: t.bodySmall),
                  ],
                ],
              ),
            ),
        ],
        // Only the long analysis stays behind "More details".
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => setState(() => _details = !_details),
            icon: Icon(_details ? Icons.expand_less : Icons.expand_more),
            label: Text(_details ? 'Less' : 'Full ACAPS analysis'),
          ),
        ),
        if (_details) ...[
          Text(r.title, style: t.titleSmall),
          const SizedBox(height: 8),
          Text(r.rationale, style: t.bodyMedium),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One trigger, four questions
// ---------------------------------------------------------------------------

class _ItemPage extends StatefulWidget {
  final SurveyItem item;
  final int index;
  final int total;
  final _Draft draft;
  final VoidCallback onChanged;

  /// Shown under the questions (the credit choice on the last screen).
  final Widget? footer;

  const _ItemPage({required this.item, required this.index, required this.total, required this.draft, required this.onChanged, this.footer});

  @override
  State<_ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<_ItemPage> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final it = widget.item;
    final d = widget.draft;
    final c = it.completion;
    void set(VoidCallback f) {
      setState(f);
      widget.onChanged();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          widget.total == 1 ? 'THE RISK' : 'TRIGGER ${widget.index + 1} OF ${widget.total}',
          style: TextStyle(fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(it.title, style: t.titleLarge),
        if (c != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: c / 100,
                    minHeight: 8,
                    color: Color.lerp(scaleColors[1], scaleColors[4], c / 100),
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$c%', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text('How close ACAPS thinks this trigger is to being reached', style: t.bodySmall),
        ],
        if (it.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            it.description,
            maxLines: _more ? null : 3,
            overflow: _more ? null : TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(height: 1.45),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              onPressed: () => setState(() => _more = !_more),
              child: Text(_more ? 'Less' : 'Read more'),
            ),
          ),
        ],
        _Question(
          n: 1,
          text: c == null ? 'Do you agree with the ACAPS assessment?' : 'Do you agree with ACAPS on this trigger?',
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<Agreement>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [for (final a in Agreement.values) ButtonSegment(value: a, label: Text(a.label))],
              selected: {if (d.agree != null) d.agree!},
              onSelectionChanged: (s) => set(() => d.agree = s.firstOrNull),
            ),
          ),
        ),
        _Question(
          n: 2,
          text: 'How likely is it to happen in the next 6 months?',
          child: ScalePicker(value: d.likelihood, labels: likelihoodLabels, onSelect: (v) => set(() => d.likelihood = v)),
        ),
        _Question(
          n: 3,
          text: 'How bad would it be?',
          child: ScalePicker(value: d.severity, labels: severityLabels, onSelect: (v) => set(() => d.severity = v)),
        ),
        _Question(
          n: 4,
          text: 'What is ACAPS missing?',
          optional: true,
          child: TextField(
            controller: d.missing,
            maxLength: 140,
            maxLines: 1,
            decoration: const InputDecoration(hintText: 'One line: a signal, a place, a correction…'),
          ),
        ),
        Row(
          children: [
            Icon(Icons.lock_outline, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                appState.me!.hideFromOtherCountries
                    ? 'Colleagues from ${appState.me!.homeCountry} see your comment as ${nameSeenBy(appState.me!, ViewerRole.expert, sameCountry: true)}, '
                        'others as $anonymousName. The public never sees it.'
                    : 'Colleagues see your comment as ${nameSeenBy(appState.me!, ViewerRole.expert)}. The public never sees it.',
                style: t.bodySmall,
              ),
            ),
          ],
        ),
        if (widget.footer != null) ...[const SizedBox(height: 24), widget.footer!],
      ],
    );
  }
}

/// "If ACAPS publishes this risk, list me as ..." Defaults to the profile.
class CreditPicker extends StatelessWidget {
  final Expert expert;
  final Credit value;
  final ValueChanged<Credit> onChanged;
  const CreditPicker({super.key, required this.expert, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final shown = publicCredit(expert, value);
    final isDefault = value == defaultCredit(expert);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('If ACAPS publishes this risk, credit me as', style: t.titleSmall)),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<Credit>(
              showSelectedIcon: false,
              segments: [
                for (final c in Credit.values)
                  ButtonSegment(value: c, label: Text(c.label), enabled: creditAllowed(expert, c)),
              ],
              selected: {value},
              onSelectionChanged: (v) => onChanged(v.first),
            ),
            const SizedBox(height: 8),
            Text(
              '${shown == null ? 'Not listed. Your answers only count in the totals.' : 'Listed among contributors as "${shown.name}".'} '
              'Names are never shown next to answers.'
              '${isDefault ? ' This is the default from your profile.' : ''}'
              '${expert.realName == null ? ' Real name is off: your profile is fully anonymous.' : ''}',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Question extends StatelessWidget {
  final int n;
  final String text;
  final bool optional;
  final Widget child;
  const _Question({required this.n, required this.text, required this.child, this.optional = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: cs.primary.withAlpha(30),
                child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.primary)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              if (optional) Text('optional', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// 1..5 picker.
class ScalePicker extends StatelessWidget {
  final int? value;
  final List<String> labels;
  final ValueChanged<int> onSelect;
  const ScalePicker({super.key, required this.value, required this.labels, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: value == i ? scaleColors[i - 1] : scaleColors[i - 1].withAlpha(26),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scaleColors[i - 1].withAlpha(value == i ? 255 : 80), width: 1.5),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(i),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$i',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: value == i ? Colors.white : scaleColors[i - 1])),
                        Text(
                          labels[i - 1],
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(fontSize: 9.5, height: 1.1, color: value == i ? Colors.white : cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thank you + group summary
// ---------------------------------------------------------------------------

class _Summary extends StatelessWidget {
  final Risk risk;
  const _Summary({required this.risk});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final me = appState.me;
    final mine = me == null ? null : appState.responseOf(me, risk);
    final panel = appState.panelForRisk(risk);
    final answered = appState.respondents(risk);
    final comments = appState.commentsOn(risk);
    final items = risk.surveyItems;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (mine != null)
          Reveal(
            child: Row(
              children: [
                Icon(Icons.volunteer_activism_outlined, color: cs.primary, size: 30),
                const SizedBox(width: 12),
                Expanded(child: Text('Thank you. Here is how your group sees it.', style: t.titleMedium)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (risk.isResolved && mine == null) ...[
          InfoBanner(
            icon: Icons.lock_clock_outlined,
            text: 'This risk has closed. You can see what happened and how the group saw it. '
                'Answers are no longer accepted, so there are no points here.',
          ),
          const SizedBox(height: 12),
          MaturedBlock(risk: risk),
          const SizedBox(height: 12),
        ],
        RespondentsCard(risk: risk, answered: answered, panelSize: panel.length),
        if (risk.isResolved && mine != null) ...[
          const SectionLabel('Your forecast matured'),
          MaturedBlock(risk: risk, response: mine),
        ],
        // Per question: results, then what colleagues say ACAPS is missing, then the next question.
        for (var i = 0; i < items.length; i++) ...[
          QuestionHeader(number: i + 1, total: items.length, title: items[i].title),
          ItemSummary(risk: risk, item: items[i], mine: mine?.items[items[i].id]),
          CommentGroup(
            comments: comments.where((c) => c.itemId == items[i].id).toList()
              ..sort((a, b) => b.agreeIds.length.compareTo(a.agreeIds.length)),
          ),
          if (i < items.length - 1) const Divider(height: 36),
        ],
      ],
    );
  }
}

/// "6 of 8 answered", split into experts from the risk country and from elsewhere.
class RespondentsCard extends StatelessWidget {
  final Risk risk;
  final List<Expert> answered;
  final int panelSize;
  const RespondentsCard({super.key, required this.risk, required this.answered, required this.panelSize});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rc = AppState.riskCountries(risk);
    final split = splitByRiskCountry(answered, rc);
    final localN = split.local.fold(0, (a, x) => a + x.n);
    final otherN = split.other.fold(0, (a, x) => a + x.n);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${answered.length}', style: t.headlineMedium?.copyWith(color: cs.primary)),
                Text(' of $panelSize', style: t.titleMedium),
                const SizedBox(width: 12),
                Expanded(child: Text('experts on this panel have answered. Names are never shown here.', style: t.bodySmall)),
              ],
            ),
            const SizedBox(height: 12),
            _SplitRow(icon: Icons.place, label: 'From ${rc.join(', ')}', n: localN),
            const SizedBox(height: 6),
            _SplitRow(
              icon: Icons.public,
              label: 'From other countries',
              n: otherN,
              detail: split.other.isEmpty ? null : countryList(split.other),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int n;
  final String? detail;
  const _SplitRow({required this.icon, required this.label, required this.n, this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (detail != null) Text(detail!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        Text('$n', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class ItemSummary extends StatelessWidget {
  final Risk risk;
  final SurveyItem item;
  final ItemAnswer? mine;
  const ItemSummary({super.key, required this.risk, required this.item, required this.mine});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final answers = appState.answersFor(risk, item.id);
    List<int> count(int Function(ItemAnswer) f) {
      final c = List.filled(5, 0);
      for (final a in answers) {
        c[f(a) - 1]++;
      }
      return c;
    }

    final agree = {for (final a in Agreement.values) a: answers.where((x) => x.agree == a).length};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Agree with ACAPS', style: t.labelLarge),
            const SizedBox(height: 8),
            AgreementBar(counts: agree, mine: mine?.agree),
            const SizedBox(height: 16),
            Text('Likelihood in 6 months', style: t.labelLarge),
            Distribution(counts: count((a) => a.likelihood), mine: mine?.likelihood, acaps: risk.acapsLikelihood),
            const SizedBox(height: 12),
            Text('How bad it would be', style: t.labelLarge),
            Distribution(counts: count((a) => a.severity), mine: mine?.severity, acaps: risk.impact),
          ],
        ),
      ),
    );
  }
}

const agreementColors = {
  Agreement.yes: Color(0xFF4E9A61),
  Agreement.partly: Color(0xFFD1A03A),
  Agreement.no: Color(0xFFB03A2E),
};

/// Read-only stacked bar of yes / partly / no, with a plain-text legend.
/// Deliberately not chip-shaped, so it doesn't look tappable.
class AgreementBar extends StatelessWidget {
  final Map<Agreement, int> counts;
  final Agreement? mine;
  const AgreementBar({super.key, required this.counts, this.mine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = counts.values.fold(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            width: double.infinity,
            child: total == 0
                ? Container(color: cs.surfaceContainerHighest)
                : Row(
                    children: [
                      for (final a in Agreement.values)
                        if (counts[a]! > 0) Expanded(flex: counts[a]!, child: Container(color: agreementColors[a]!)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final a in Agreement.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: agreementColors[a], shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('${a.label} ${counts[a]}',
                      style: TextStyle(fontSize: 13, fontWeight: mine == a ? FontWeight.w800 : FontWeight.w400)),
                  if (mine == a)
                    Text('  (you)', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// "Trigger 1 of 3" + title, opening each question block.
class QuestionHeader extends StatelessWidget {
  final int number;
  final int total;
  final String title;
  const QuestionHeader({super.key, required this.number, required this.total, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primary,
            child: Text('$number', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(total == 1 ? 'THE RISK' : 'TRIGGER $number OF $total',
                    style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: cs.primary)),
                Text(title, style: t.titleSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Colleagues' additions for one question, shown right under its results.
class CommentGroup extends StatelessWidget {
  final List<Comment> comments;
  const CommentGroup({super.key, required this.comments});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 12, left: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: cs.primary.withAlpha(150), width: 3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text('What ACAPS is missing · ${comments.length}', style: t.labelLarge),
            ],
          ),
          const SizedBox(height: 4),
          if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Nothing added on this one yet.', style: t.bodySmall),
            )
          else
            for (final c in comments) CommentCard(comment: c, items: const []),
        ],
      ),
    );
  }
}

/// Bar chart over 1..5 with "you are here" and the ACAPS rating marked.
/// Bars and labels are separate rows, so labels never squeeze the bars
/// (and grow with the text size setting).
class Distribution extends StatelessWidget {
  final List<int> counts;
  final int? mine;
  final int? acaps;
  const Distribution({super.key, required this.counts, this.mine, this.acaps});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxC = counts.fold(1, (a, b) => a > b ? a : b);
    Widget cell(Widget child) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: child));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 1; i <= 5; i++)
                cell(Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${counts[i - 1]}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Container(
                      height: 6 + 54.0 * counts[i - 1] / maxC,
                      decoration: BoxDecoration(
                        color: scaleColors[i - 1].withAlpha(mine == i ? 255 : 130),
                        borderRadius: BorderRadius.circular(6),
                        border: mine == i ? Border.all(color: cs.onSurface, width: 2) : null,
                      ),
                    ),
                  ],
                )),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 1; i <= 5; i++)
                cell(Column(
                  children: [
                    Text('$i', style: TextStyle(fontWeight: mine == i ? FontWeight.w800 : FontWeight.w500)),
                    if (mine == i)
                      const Text('you are here', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
                    if (acaps == i)
                      const Padding(padding: EdgeInsets.only(top: 2), child: FittedBox(fit: BoxFit.scaleDown, child: Pill('ACAPS'))),
                  ],
                )),
            ],
          ),
        ],
      ),
    );
  }
}

/// Outcome of a closed risk, styled like the risk card. With [response], also
/// the expert's score for the forecast they made while it was open.
class MaturedBlock extends StatelessWidget {
  final Risk risk;
  final Response? response;
  const MaturedBlock({super.key, required this.risk, this.response});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = response == null ? null : appState.scoreOf(response!);
    final happened = risk.materialised;
    final accent = happened ? AppColors.high : scaleColors[1];
    final text = risk.materialisation.length > 360 ? '${risk.materialisation.substring(0, 360).trimRight()}…' : risk.materialisation;

    return RiskHeader(
      risk: risk,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(happened ? Icons.warning_amber_rounded : Icons.shield_outlined, color: accent),
              const SizedBox(width: 8),
              Text(happened ? 'What happened: it materialised' : 'What happened: it did not materialise',
                  style: t.titleSmall?.copyWith(color: accent)),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(text, style: t.bodySmall?.copyWith(height: 1.45)),
          ],
          if (s != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                ScoreBox(label: 'Your accuracy', value: '${accuracyPct(s.mine)}%', highlight: true),
                const SizedBox(width: 8),
                ScoreBox(label: 'ACAPS accuracy', value: '${accuracyPct(s.acaps)}%'),
                const SizedBox(width: 8),
                ScoreBox(label: 'Points', value: '+${s.points}'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${s.mine < s.acaps - 0.005 ? 'You were closer than ACAPS.' : s.mine > s.acaps + 0.005 ? 'ACAPS was closer this time.' : 'Same as ACAPS.'} '
              'Accuracy: how close your "how likely" answers were to what happened (100% = perfect). Only likelihood is scored.',
              style: t.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class ScoreBox extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const ScoreBox({super.key, required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: highlight ? cs.primary.withAlpha(30) : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// A colleague comment with agree/disagree. Hovering (or long-pressing) a
/// button shows where those experts are from, never singling anyone out.
class CommentCard extends StatelessWidget {
  final Comment comment;
  final List<SurveyItem> items;
  final Widget? moderatorActions;
  const CommentCard({super.key, required this.comment, required this.items, this.moderatorActions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = comment;
    final author = appState.expertById(c.authorId);
    final viewer = appState.viewer;
    final name = author == null ? anonymousName : displayName(author, viewer);
    final me = appState.me;
    final isMine = me != null && c.authorId == me.id;
    final item = items.where((i) => i.id == c.itemId).firstOrNull;
    final risk = appState.byId(c.riskId);
    final rc = risk == null ? <String>[] : AppState.riskCountries(risk);
    // Closed risks are read-only, reactions included.
    final canReact = me != null && !isMine && !(risk?.isResolved ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(name, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (isMine) const Pill('You', strong: true),
                ],
              ),
              if (item != null && items.length > 1) ...[
                const SizedBox(height: 4),
                Text('On: ${item.title}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 8),
              Text(c.text, style: const TextStyle(height: 1.4)),
              if (c.useful || c.usedInRiskId != null) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (c.useful) const Pill('Marked useful by ACAPS', icon: Icons.lightbulb_outline),
                  if (c.usedInRiskId != null) Pill('Used in ${c.usedInRiskId}', icon: Icons.push_pin_outlined),
                ]),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ReactChip(
                    icon: Icons.thumb_up_alt_outlined,
                    label: 'Agree',
                    ids: c.agreeIds,
                    riskCountries: rc,
                    active: me != null && c.agreeIds.contains(me.id),
                    onTap: canReact ? () => appState.react(c, true) : null,
                  ),
                  _ReactChip(
                    icon: Icons.thumb_down_alt_outlined,
                    label: 'Disagree',
                    ids: c.disagreeIds,
                    riskCountries: rc,
                    active: me != null && c.disagreeIds.contains(me.id),
                    onTap: canReact ? () => appState.react(c, false) : null,
                  ),
                ],
              ),
              if (moderatorActions != null) ...[const Divider(height: 20), moderatorActions!],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Set<String> ids;
  final List<String> riskCountries;
  final bool active;
  final VoidCallback? onTap;

  const _ReactChip({required this.icon, required this.label, required this.ids, required this.riskCountries, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.primary : cs.onSurfaceVariant;
    final where = describeSplit(appState.expertsByIds(ids), riskCountries);
    return Tooltip(
      message: where,
      waitDuration: const Duration(milliseconds: 150),
      child: Material(
        color: active ? cs.primary.withAlpha(26) : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: active ? cs.primary : cs.outlineVariant)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(active ? Icons.check : icon, size: 15, color: fg),
                const SizedBox(width: 5),
                Text('$label · ${ids.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
