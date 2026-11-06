import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'profile.dart';
import 'survey.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Entering the app from a notification, or with a new/updated risk waiting:
    // open that card straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = appState.takeAutoOpen();
      if (r == null || !mounted) return;
      final answered = appState.responseOf(appState.me!, r) != null;
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SurveyScreen(
          risk: r,
          start: answered ? SurveyStart.summary : SurveyStart.intro,
          fromNotification: true,
        ),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: const [InboxTab(), ForecastsTab(), RatingTab(), ProfileTab()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: 'Risks'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: 'My forecasts'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Rating'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Risks
// ---------------------------------------------------------------------------

class InboxTab extends StatelessWidget {
  const InboxTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final me = appState.me;
        if (me == null) return const SizedBox();
        final note = appState.pendingNotification;
        final active = appState.activeForMe();
        final practice = appState.practiceForMe();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('Hi, ${displayName(me, appState.viewer)}', style: t.headlineSmall),
            const SizedBox(height: 4),
            Text('Your countries: ${([me.homeCountry, ...me.interests]).join(', ')}', style: t.bodySmall),
            if (note != null) ...[const SizedBox(height: 16), _Notification(risk: note)],
            SectionLabel('Active risks in your countries · ${active.length}'),
            if (active.isEmpty) Text('No active risks right now.', style: t.bodySmall),
            for (final r in active) RiskTile(risk: r),
            if (practice.isNotEmpty) ...[
              const SectionLabel('Archive · practise and see what happened'),
              for (final r in practice.take(5)) RiskTile(risk: r, trailing: 'matures instantly'),
            ],
          ],
        );
      },
    );
  }
}

/// In-app version of the push notification.
class _Notification extends StatelessWidget {
  final Risk risk;
  const _Notification({required this.risk});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final n = risk.surveyItems.length;
    final country = AppState.riskCountries(risk).first;
    return Reveal(
      child: Card(
        color: cs.primary.withAlpha(22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.primary.withAlpha(120))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('ACAPS · now', style: t.labelMedium),
                ],
              ),
              const SizedBox(height: 10),
              Text('ACAPS updated a risk in $country. Got 2 minutes? $n short ${n == 1 ? 'question' : 'questions'}.',
                  style: t.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(onPressed: () => appState.skip(risk), child: const Text('Not now')),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SurveyScreen(risk: risk))),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My forecasts
// ---------------------------------------------------------------------------

class ForecastsTab extends StatelessWidget {
  const ForecastsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final me = appState.me;
        if (me == null) return const SizedBox();
        final all = appState.responsesOf(me);
        final open = all.where((x) => !(appState.byId(x.riskId)?.isResolved ?? false)).toList();
        final matured = all.where((x) => appState.byId(x.riskId)?.isResolved ?? false).toList();
        final st = appState.statsOf(me);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('My forecasts', style: t.headlineSmall),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    _Stat(value: '${all.length}', label: 'answered'),
                    _Stat(value: '${matured.length}', label: 'matured'),
                    _Stat(value: st.brier == null ? '-' : '${accuracyPct(st.brier!)}%', label: 'accuracy'),
                    _Stat(value: '${st.points}', label: 'points'),
                  ],
                ),
              ),
            ),
            SectionLabel('Open · ${open.length}'),
            if (open.isEmpty) Text('Nothing open. Answer a risk from the Risks tab.', style: t.bodySmall),
            for (final x in open) _ForecastCard(response: x),
            SectionLabel('Matured · ${matured.length}'),
            if (matured.isEmpty)
              Text('A forecast matures when the 6-month window closes. Try an archive risk to see one now.', style: t.bodySmall),
            for (final x in matured) _ForecastCard(response: x),
          ],
        );
      },
    );
  }
}

class _ForecastCard extends StatelessWidget {
  final Response response;
  const _ForecastCard({required this.response});

  @override
  Widget build(BuildContext context) {
    final r = appState.byId(response.riskId)!;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final when = response.editedAt ?? response.answeredAt;
    final items = r.surveyItems;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: r.isResolved
          ? MaturedBlock(risk: r, response: response)
          : Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${r.id} · ${r.country}',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
                        ),
                        Text('${response.editedAt == null ? 'Answered' : 'Edited'} ${formatDate(when)}', style: t.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(r.oneLiner, style: t.titleSmall),
                    const SizedBox(height: 8),
                    for (final it in items)
                      if (response.items[it.id] case final a?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${items.length > 1 ? '${it.title}: ' : ''}agree ${a.agree.label.toLowerCase()} · likely ${a.likelihood}/5 · bad ${a.severity}/5',
                            style: t.bodySmall,
                          ),
                        ),
                    Text('Matures ${formatDate(response.answeredAt.add(const Duration(days: 182)))}', style: t.bodySmall),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SurveyScreen(risk: r, start: SurveyStart.summary))),
                          icon: const Icon(Icons.bar_chart, size: 18),
                          label: const Text('Group view'),
                        ),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SurveyScreen(risk: r, start: SurveyStart.questions))),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rating
// ---------------------------------------------------------------------------

class RatingTab extends StatefulWidget {
  const RatingTab({super.key});

  @override
  State<RatingTab> createState() => _RatingTabState();
}

class _RatingTabState extends State<RatingTab> {
  late RatingScope _scope = appState.me == null ? RatingScope.all : RatingScope.country;
  late String _country = appState.me?.homeCountry ?? 'Chad';
  late String _region = regionOf(_country);

  bool _matches(Expert e) => switch (_scope) {
        RatingScope.country => e.homeCountry == _country,
        RatingScope.region => regionOf(e.homeCountry) == _region,
        RatingScope.all => true,
      };

  bool _riskMatches(Risk r) {
    final cs = AppState.riskCountries(r);
    return switch (_scope) {
      RatingScope.country => cs.contains(_country),
      RatingScope.region => cs.any((c) => regionOf(c) == _region),
      RatingScope.all => true,
    };
  }

  String get _scopeName => switch (_scope) {
        RatingScope.country => _country,
        RatingScope.region => _region,
        RatingScope.all => 'all countries',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final me = appState.me;
        final viewer = appState.viewer;
        final rows = appState.rating(where: _matches, riskWhere: _riskMatches);
        final people = rows.where((r) => r.expert != null).toList();
        final acaps = rows.firstWhere((r) => r.expert == null);
        final countries = appState.countries;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text('Rating', style: t.headlineSmall)),
                IconButton(
                  tooltip: 'How scoring works',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => showScoringHelp(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<RatingScope>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: RatingScope.country, label: Text(me == null ? 'Country' : 'My country'), icon: const Icon(Icons.place_outlined)),
                  ButtonSegment(value: RatingScope.region, label: Text(me == null ? 'Region' : 'My region'), icon: const Icon(Icons.map_outlined)),
                  const ButtonSegment(value: RatingScope.all, label: Text('All'), icon: Icon(Icons.public)),
                ],
                selected: {_scope},
                onSelectionChanged: (v) => setState(() => _scope = v.first),
              ),
            ),
            if (_scope != RatingScope.all) ...[
              const SizedBox(height: 10),
              DropdownMenu<String>(
                key: ValueKey(_scope),
                expandedInsets: EdgeInsets.zero,
                menuHeight: 320,
                initialSelection: _scope == RatingScope.country ? _country : _region,
                label: Text(_scope == RatingScope.country ? 'Country' : 'Region'),
                leadingIcon: Icon(_scope == RatingScope.country ? Icons.place_outlined : Icons.map_outlined),
                dropdownMenuEntries: [
                  for (final c in _scope == RatingScope.country ? countries : regions.keys.toList())
                    DropdownMenuEntry(value: c, label: c),
                ],
                onSelected: (v) {
                  if (v == null) return;
                  setState(() => _scope == RatingScope.country ? _country = v : _region = v);
                },
              ),
            ],
            if (me != null && !me.onRating) ...[
              const SizedBox(height: 12),
              InfoBanner(icon: Icons.visibility_off_outlined, text: 'You are not in the rating. Turn it on in Profile.', color: cs.primary),
            ],
            const SizedBox(height: 12),
            if (people.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No experts in the rating here yet. Try "My region" or "All".', style: t.bodyMedium),
                ),
              )
            else
              for (var i = 0; i < people.length; i++)
                _RatingTile(
                  rank: i + 1,
                  name: displayName(people[i].expert!, viewer),
                  row: people[i],
                  isMe: people[i].expert!.id == me?.id,
                ),
            const SizedBox(height: 8),
            _Benchmark(row: acaps, scopeName: _scopeName),
            const SectionLabel('How you earn points'),
            _PointsRow(icon: Icons.track_changes, text: 'Matured forecast: up to 100 points, equal to your accuracy'),
            _PointsRow(icon: Icons.lightbulb_outline, text: '+${Points.usefulComment}: a moderator marks your comment as useful'),
            _PointsRow(icon: Icons.push_pin_outlined, text: '+${Points.usedComment}: your comment is used in the analysis of another risk'),
            const SectionLabel('Badges'),
            for (final b in Award.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AwardIcon(b),
                title: Text(b.label),
                subtitle: Text(b.why),
              ),
          ],
        );
      },
    );
  }
}

/// The bar to beat: how accurate ACAPS's own published probabilities were.
class _Benchmark extends StatelessWidget {
  final RatingRow row;
  final String scopeName;
  const _Benchmark({required this.row, required this.scopeName});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline, width: 1.5, style: BorderStyle.solid),
        color: cs.surfaceContainerHighest.withAlpha(110),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_circle_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Bar to beat: ACAPS itself', style: t.titleSmall)),
              Text(row.brier == null ? '-' : '${accuracyPct(row.brier!)}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            row.brier == null
                ? 'No resolved ACAPS risks in $scopeName yet, so there is nothing to compare with here.'
                : 'For each of the ${row.resolved} resolved risks in $scopeName, ACAPS published a probability '
                    '(e.g. "High" ≈ 70%). We score those ratings exactly like yours. '
                    'If your accuracy is higher, your forecasts beat the published analysis.',
            style: t.bodySmall,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
              onPressed: () => showScoringHelp(context),
              child: const Text('How accuracy is scored'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain-language explanation of accuracy and the Brier score.
void showScoringHelp(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('How accuracy is scored'),
        content: const SingleChildScrollView(
          child: Text(
            'When a forecast matures, we check what actually happened.\n\n'
            'Accuracy: how close your "how likely" answers were to reality. '
            '100% means you were sure and right; 0% means you were sure and wrong.\n\n'
            'Example: you said "Very likely" (90%) and it happened: accuracy 99%. '
            'You said "Even chance" (50%): accuracy 75%, whatever happened.\n\n'
            'Behind it is the Brier score, a standard measure for forecasts: the squared gap '
            'between your probability and the outcome (0 = perfect, 1 = worst). '
            'Accuracy = 100 × (1 − Brier).\n\n'
            'Only likelihood is scored. "How bad" is not scored yet.\n\n'
            'Bar to beat: ACAPS publishes a probability for every risk. We score those '
            'published ratings against what happened, the same way, as a benchmark.',
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Got it'))],
      ),
    );

class _PointsRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PointsRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

/// Gold, silver, bronze.
const _podium = [Color(0xFFE0A800), Color(0xFF9AA4AE), Color(0xFFB8733A)];

class _RatingTile extends StatelessWidget {
  final int rank;
  final String name;
  final RatingRow row;
  final bool isMe;
  const _RatingTile({required this.rank, required this.name, required this.row, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final podium = rank <= 3 ? _podium[rank - 1] : null;
    final bg = podium != null ? podium.withAlpha(48) : (isMe ? cs.primary.withAlpha(26) : cs.surfaceContainerLowest);
    final border = podium ?? (isMe ? cs.primary : cs.outlineVariant);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: podium != null ? 14 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: podium != null || isMe ? 2 : 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: podium != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.emoji_events, color: podium, size: 34),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('$rank', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                    ],
                  )
                : Text('$rank', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Avatar(name, size: podium != null ? 36 : 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '$name (you)' : name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: podium != null || isMe ? FontWeight.w800 : FontWeight.w600, fontSize: podium != null ? 15.5 : 14)),
                Text(
                  row.brier == null ? 'No matured forecasts yet' : 'Accuracy ${accuracyPct(row.brier!)}% · ${row.resolved} matured',
                  style: t.bodySmall,
                ),
                if (row.badges.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 4, children: [for (final b in row.badges) AwardIcon(b, size: 20)]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${row.points}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: podium != null ? 20 : 16)),
              Text('points', style: t.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class AwardIcon extends StatelessWidget {
  final Award badge;
  final double size;
  const AwardIcon(this.badge, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (badge) {
      Award.superEstimator => (Icons.track_changes, const Color(0xFFD9A441)),
      Award.usefulInsight => (Icons.lightbulb_outline, const Color(0xFF6E9E72)),
      Award.cited => (Icons.push_pin_outlined, const Color(0xFF2E7DAF)),
      Award.regular => (Icons.repeat, const Color(0xFF8A6FB0)),
    };
    return Tooltip(
      message: badge.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withAlpha(40), shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.6, color: color),
      ),
    );
  }
}
