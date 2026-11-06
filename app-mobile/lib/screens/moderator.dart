import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';
import 'survey.dart';

/// Moderator workspace.
///
/// Overview: what needs attention now. Risks: filter, sort and review one risk
/// (results per question with the comments right underneath, actions inline).
/// Panels: coverage per country and the experts in each. Rating: as experts see it.
class ModeratorShell extends StatefulWidget {
  const ModeratorShell({super.key});

  @override
  State<ModeratorShell> createState() => _ModeratorShellState();
}

const _wideBreakpoint = 900.0;

class _ModeratorShellState extends State<ModeratorShell> {
  /// Demo links can open a tab directly: ?tab=overview|risks|panels|rating.
  int _tab = const ['overview', 'risks', 'panels', 'rating'].indexOf(Uri.base.queryParameters['tab'] ?? '').clamp(0, 3);
  final _filter = RiskFilter();
  String? _selectedRisk = 'R1043';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _openRisk(Risk r) {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    setState(() {
      _tab = 1;
      _selectedRisk = r.id;
    });
    if (!wide) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModRiskScreen(risk: r)));
    }
  }

  void _showToReview() {
    _filter.update((f) {
      f.clear();
      f.status = RiskStatus.all;
      f.onlyToReview = true;
      f.sort = RiskSort.toReview;
    });
    setState(() => _tab = 1);
  }

  static const _dest = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Overview'),
    (Icons.fact_check_outlined, Icons.fact_check, 'Risks'),
    (Icons.groups_2_outlined, Icons.groups_2, 'Panels'),
    (Icons.emoji_events_outlined, Icons.emoji_events, 'Rating'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final body = ListenableBuilder(
      listenable: appState,
      builder: (context, _) => IndexedStack(
        index: _tab,
        children: [
          _OverviewTab(onOpenRisk: _openRisk, onShowToReview: _showToReview, onShowPanels: () => setState(() => _tab = 2)),
          _RisksTab(
            filter: _filter,
            selectedId: _selectedRisk,
            onSelect: (r) {
              if (wide) {
                setState(() => _selectedRisk = r.id);
              } else {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModRiskScreen(risk: r)));
              }
            },
          ),
          const _PanelsTab(),
          const RatingTab(),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_outlined),
            const SizedBox(width: 8),
            const Flexible(child: Text('ACAPS moderator', style: TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final n = appState.commentsToReview;
                return n == 0 ? const SizedBox() : Badge(label: Text('$n'), child: const Icon(Icons.forum_outlined, size: 20));
              },
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Theme and text size', onPressed: () => showDisplaySettings(context), icon: const Icon(Icons.text_fields)),
          IconButton(tooltip: 'Switch user', onPressed: appState.signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
    );
  }
}

// ===========================================================================
// Overview
// ===========================================================================

class _OverviewTab extends StatelessWidget {
  final ValueChanged<Risk> onOpenRisk;
  final VoidCallback onShowToReview;
  final VoidCallback onShowPanels;
  const _OverviewTab({required this.onOpenRisk, required this.onShowToReview, required this.onShowPanels});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final active = appState.risks.where((r) => r.isActive).toList();
    final stats = {for (final r in active) r.id: appState.modStats(r)};
    final withPanel = active.where((r) => stats[r.id]!.panel > 0).toList();
    final rate = withPanel.isEmpty ? 0.0 : withPanel.fold(0.0, (s, r) => s + stats[r.id]!.responseRate) / withPanel.length;
    final toReview = appState.comments.where((c) => c.needsReview).toList();
    final thin = appState.thinPanels;
    final divergent = withPanel.where((r) => stats[r.id]!.answered >= minPanel).toList()
      ..sort((a, b) => _attention(stats[b.id]!).compareTo(_attention(stats[a.id]!)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Overview', style: t.headlineSmall),
        const SizedBox(height: 4),
        Text('What needs your attention today.', style: t.bodySmall),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, box) {
          final kw = box.maxWidth < 560 ? (box.maxWidth - 10) / 2 : 160.0;
          return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Kpi(width: kw, icon: Icons.bolt, value: '${active.length}', label: 'active risks'),
            _Kpi(width: kw, icon: Icons.how_to_vote_outlined, value: '${(rate * 100).round()}%', label: 'response rate', hint: 'average over risks that have a panel'),
            _Kpi(
              width: kw,
              icon: Icons.forum_outlined,
              value: '${toReview.length}',
              label: 'comments to review',
              color: toReview.isEmpty ? null : cs.error,
              onTap: onShowToReview,
            ),
            _Kpi(
              width: kw,
              icon: Icons.warning_amber_rounded,
              value: '${active.where((r) => stats[r.id]!.panel < minPanel).length}',
              label: 'risks without a full panel',
              color: cs.tertiary,
              onTap: onShowPanels,
            ),
          ],
        );
        }),

        _SectionHeader(
          icon: Icons.forum_outlined,
          title: 'Comments waiting for review',
          action: toReview.isEmpty ? null : TextButton(onPressed: onShowToReview, child: const Text('Review all')),
        ),
        if (toReview.isEmpty)
          const _Empty('All comments reviewed.')
        else
          for (final c in toReview.take(4))
            if (appState.byId(c.riskId) case final r?)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  onTap: () => onOpenRisk(r),
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(c.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${r.id} · ${r.country} · ${_itemTitle(r, c.itemId)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),

        const _SectionHeader(icon: Icons.compare_arrows, title: 'Where experts see it differently from ACAPS'),
        Text('Active risks with at least $minPanel answers, biggest gap first. A signal to revisit the analysis.', style: t.bodySmall),
        const SizedBox(height: 6),
        if (divergent.isEmpty) const _Empty('Not enough answers yet.'),
        for (final r in divergent.take(5)) _DivergenceTile(risk: r, s: stats[r.id]!, onTap: () => onOpenRisk(r)),

        _SectionHeader(
          icon: Icons.person_add_alt,
          title: 'Recruitment needed',
          action: TextButton(onPressed: onShowPanels, child: const Text('All panels')),
        ),
        Text('Countries with active risks and fewer than $minPanel experts: group results there could reveal who answered.',
            style: t.bodySmall),
        const SizedBox(height: 6),
        for (final p in thin.take(5))
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: p.n == 0 ? cs.onSurfaceVariant : cs.error),
              title: Text(p.country),
              subtitle: Text('${regionOf(p.country)} · ${p.active} active ${p.active == 1 ? 'risk' : 'risks'}'),
              trailing: Text('${p.n} / $minPanel', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        if (thin.length > 5) Text('+ ${thin.length - 5} more in Panels', style: t.bodySmall),
      ],
    );
  }

  static double _attention(RiskModStats s) => (s.gap?.abs() ?? 0) + s.disagreement * 2;
}

String _itemTitle(Risk r, String itemId) => r.surveyItems.where((i) => i.id == itemId).firstOrNull?.title ?? 'Risk';

class _Kpi extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? hint;
  final Color? color;
  final VoidCallback? onTap;
  final double width;
  const _Kpi({required this.icon, required this.value, required this.label, this.hint, this.color, this.onTap, this.width = 160});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 4))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: c, size: 20),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
    return hint == null ? card : Tooltip(message: hint!, child: card);
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? action;
  const _SectionHeader({required this.icon, required this.title, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (action != null) action!,
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _DivergenceTile extends StatelessWidget {
  final Risk risk;
  final RiskModStats s;
  final VoidCallback onTap;
  const _DivergenceTile({required this.risk, required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gap = s.gap;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        title: Text(risk.oneLiner, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text('${risk.id} · ${risk.country}'),
              if (gap != null) _GapLabel(gap: gap, experts: s.expertLikelihood!, acaps: s.acapsLikelihood!),
              Text('disagree ${(s.disagreement * 100).round()}%'),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _GapLabel extends StatelessWidget {
  final double gap;
  final double experts;
  final int acaps;
  const _GapLabel({required this.gap, required this.experts, required this.acaps});

  @override
  Widget build(BuildContext context) {
    final up = gap > 0.25, down = gap < -0.25;
    final color = up ? AppColors.high : (down ? AppColors.low : Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.trending_up : (down ? Icons.trending_down : Icons.trending_flat), size: 16, color: color),
        const SizedBox(width: 3),
        Text('experts ${experts.toStringAsFixed(1)} vs ACAPS $acaps',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ],
    );
  }
}

// ===========================================================================
// Risks: filters + list (+ review pane on wide screens)
// ===========================================================================

enum RiskStatus { active, archive, all }

enum RiskSort { toReview, disagreement, gap, responseRate, level, id }

extension RiskSortText on RiskSort {
  String get label => switch (this) {
        RiskSort.toReview => 'Most comments to review',
        RiskSort.disagreement => 'Most disagreement with ACAPS',
        RiskSort.gap => 'Biggest likelihood gap',
        RiskSort.responseRate => 'Lowest response rate',
        RiskSort.level => 'Highest risk level',
        RiskSort.id => 'Risk ID',
      };
}

class RiskFilter extends ChangeNotifier {
  String query = '';
  String? region;
  String? country;
  RiskStatus status = RiskStatus.active;
  RiskSort sort = RiskSort.toReview;
  bool onlyToReview = false;
  double minDisagreement = 0;

  void update(void Function(RiskFilter f) f) {
    f(this);
    notifyListeners();
  }

  void clear() {
    query = '';
    region = null;
    country = null;
    status = RiskStatus.active;
    sort = RiskSort.toReview;
    onlyToReview = false;
    minDisagreement = 0;
  }

  int get activeCount =>
      (query.isEmpty ? 0 : 1) +
      (region == null ? 0 : 1) +
      (country == null ? 0 : 1) +
      (status == RiskStatus.active ? 0 : 1) +
      (onlyToReview ? 1 : 0) +
      (minDisagreement > 0 ? 1 : 0);

  List<(Risk, RiskModStats)> apply(List<Risk> risks) {
    final q = query.toLowerCase();
    final out = <(Risk, RiskModStats)>[];
    for (final r in risks) {
      if (status == RiskStatus.active && !r.isActive) continue;
      if (status == RiskStatus.archive && !r.isResolved) continue;
      if (status == RiskStatus.all && !r.isActive && !r.isResolved) continue;
      final cs = AppState.riskCountries(r);
      if (country != null && !cs.contains(country)) continue;
      if (region != null && !cs.any((c) => regionOf(c) == region)) continue;
      if (q.isNotEmpty && !'${r.id} ${r.title} ${r.country}'.toLowerCase().contains(q)) continue;
      final s = appState.modStats(r);
      if (onlyToReview && s.toReview == 0) continue;
      if (s.disagreement < minDisagreement) continue;
      out.add((r, s));
    }
    int lvl(Risk r) => switch (r.level) { 'High' => 3, 'Medium' => 2, 'Low' => 1, _ => 0 };
    out.sort((a, b) => switch (sort) {
          RiskSort.toReview => b.$2.toReview != a.$2.toReview ? b.$2.toReview.compareTo(a.$2.toReview) : b.$2.comments.compareTo(a.$2.comments),
          RiskSort.disagreement => b.$2.disagreement.compareTo(a.$2.disagreement),
          RiskSort.gap => (b.$2.gap?.abs() ?? -1).compareTo(a.$2.gap?.abs() ?? -1),
          RiskSort.responseRate => a.$2.responseRate.compareTo(b.$2.responseRate),
          RiskSort.level => lvl(b.$1).compareTo(lvl(a.$1)),
          RiskSort.id => a.$1.id.compareTo(b.$1.id),
        });
    return out;
  }
}

class _RisksTab extends StatelessWidget {
  final RiskFilter filter;
  final String? selectedId;
  final ValueChanged<Risk> onSelect;
  const _RisksTab({required this.filter, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= _wideBreakpoint - 80;
        final list = ListenableBuilder(
          listenable: filter,
          builder: (context, _) => _RiskList(filter: filter, selectedId: wide ? selectedId : null, onSelect: onSelect, compact: !wide),
        );
        if (!wide) return list;
        final selected = selectedId == null ? null : appState.byId(selectedId!);
        return Row(
          children: [
            SizedBox(width: 420, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const Center(child: Text('Pick a risk on the left.'))
                  : ModRiskReview(key: ValueKey(selected.id), risk: selected),
            ),
          ],
        );
      },
    );
  }
}

class _RiskList extends StatelessWidget {
  final RiskFilter filter;
  final String? selectedId;
  final ValueChanged<Risk> onSelect;
  final bool compact;
  const _RiskList({required this.filter, required this.selectedId, required this.onSelect, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = filter.apply(appState.risks);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        compact ? _CompactFilterBar(filter: filter) : _FilterPanel(filter: filter),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: [
              Expanded(child: Text('${rows.length} ${rows.length == 1 ? 'risk' : 'risks'}', style: t.labelLarge)),
              if (filter.activeCount > 0)
                TextButton.icon(
                  onPressed: () => filter.update((f) => f.clear()),
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear filters'),
                ),
            ],
          ),
        ),
        if (rows.isEmpty) const _Empty('No risks match these filters.'),
        for (final (r, s) in rows) _ModRiskTile(risk: r, s: s, selected: r.id == selectedId, onTap: () => onSelect(r)),
      ],
    );
  }
}

/// Phone: search + "Filters" button (opens a sheet) + removable chips for active filters.
class _CompactFilterBar extends StatefulWidget {
  final RiskFilter filter;
  const _CompactFilterBar({required this.filter});

  @override
  State<_CompactFilterBar> createState() => _CompactFilterBarState();
}

class _CompactFilterBarState extends State<_CompactFilterBar> {
  late final _search = TextEditingController(text: widget.filter.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openSheet() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: ListenableBuilder(
            listenable: widget.filter,
            builder: (context, _) {
              final n = widget.filter.apply(appState.risks).length;
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _FilterPanel(filter: widget.filter, showSearch: false),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Row(
                        children: [
                          TextButton(onPressed: () => widget.filter.update((f) => f.clear()), child: const Text('Reset')),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Show $n ${n == 1 ? 'risk' : 'risks'}'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    if (_search.text != f.query) _search.text = f.query;
    final n = f.activeCount - (f.query.isEmpty ? 0 : 1);
    final chips = <Widget>[
      if (f.status != RiskStatus.active)
        InputChip(label: Text(f.status == RiskStatus.archive ? 'Archive' : 'Active + archive'), onDeleted: () => f.update((x) => x.status = RiskStatus.active)),
      if (f.region != null) InputChip(label: Text(f.region!), onDeleted: () => f.update((x) => x.region = null)),
      if (f.country != null) InputChip(label: Text(f.country!), onDeleted: () => f.update((x) => x.country = null)),
      if (f.onlyToReview) InputChip(label: const Text('To review'), onDeleted: () => f.update((x) => x.onlyToReview = false)),
      if (f.minDisagreement > 0)
        InputChip(label: Text('Disagree ≥ ${(f.minDisagreement * 100).round()}%'), onDeleted: () => f.update((x) => x.minDisagreement = 0)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search risks', isDense: true),
                onChanged: (v) => f.update((x) => x.query = v),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: n > 0,
              label: Text('$n'),
              child: IconButton.filledTonal(
                tooltip: 'Filters and sort',
                onPressed: _openSheet,
                icon: const Icon(Icons.tune),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ActionChip(avatar: const Icon(Icons.sort, size: 18), label: Text(f.sort.label), onPressed: _openSheet),
              for (final c in chips) Padding(padding: const EdgeInsets.only(left: 6), child: c),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterPanel extends StatefulWidget {
  final RiskFilter filter;
  final bool showSearch;
  const _FilterPanel({required this.filter, this.showSearch = true});

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late final _search = TextEditingController(text: widget.filter.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = widget.filter;
    if (_search.text != f.query) _search.text = f.query; // e.g. after "Clear filters"
    final countries = (f.region == null ? appState.countries : appState.countries.where((c) => regionOf(c) == f.region)).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showSearch) ...[
              TextField(
                controller: _search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search ID, title or country', isDense: true),
                onChanged: (v) => f.update((x) => x.query = v),
              ),
              const SizedBox(height: 10),
            ],
            SegmentedButton<RiskStatus>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: RiskStatus.active, label: Text('Active')),
                ButtonSegment(value: RiskStatus.archive, label: Text('Archive')),
                ButtonSegment(value: RiskStatus.all, label: Text('All')),
              ],
              selected: {f.status},
              onSelectionChanged: (v) => f.update((x) => x.status = v.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownMenu<String?>(
                    key: ValueKey('region-${f.region}'),
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: f.region,
                    label: const Text('Region'),
                    textStyle: const TextStyle(fontSize: 13.5),
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(value: null, label: 'All regions'),
                      for (final r in regions.keys) DropdownMenuEntry(value: r, label: r),
                    ],
                    onSelected: (v) => f.update((x) {
                      x.region = v;
                      if (v != null && x.country != null && regionOf(x.country!) != v) x.country = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownMenu<String?>(
                    key: ValueKey('country-${f.country}-${f.region}'),
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: f.country,
                    menuHeight: 320,
                    label: const Text('Country'),
                    textStyle: const TextStyle(fontSize: 13.5),
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(value: null, label: 'All countries'),
                      for (final c in countries) DropdownMenuEntry(value: c, label: c),
                    ],
                    onSelected: (v) => f.update((x) => x.country = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownMenu<RiskSort>(
              key: ValueKey('sort-${f.sort}'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: f.sort,
              label: const Text('Sort by'),
              leadingIcon: const Icon(Icons.sort),
              textStyle: const TextStyle(fontSize: 13.5),
              dropdownMenuEntries: [for (final s in RiskSort.values) DropdownMenuEntry(value: s, label: s.label)],
              onSelected: (v) {
                if (v != null) f.update((x) => x.sort = v);
              },
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: f.onlyToReview,
              onChanged: (v) => f.update((x) => x.onlyToReview = v),
              title: const Text('Only risks with comments to review'),
            ),
            Row(
              children: [
                Expanded(child: Text('Disagreement with ACAPS at least', style: t.bodyMedium)),
                Text('${(f.minDisagreement * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            Slider(
              value: f.minDisagreement,
              divisions: 20,
              label: '${(f.minDisagreement * 100).round()}%',
              onChanged: (v) => f.update((x) => x.minDisagreement = v),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModRiskTile extends StatelessWidget {
  final Risk risk;
  final RiskModStats s;
  final bool selected;
  final VoidCallback onTap;
  const _ModRiskTile({required this.risk, required this.s, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: selected ? cs.primary.withAlpha(28) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${risk.id} · ${risk.country}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
                  ),
                  if (s.toReview > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(10)),
                      child: Text('${s.toReview} to review', style: TextStyle(color: cs.onError, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                  const SizedBox(width: 6),
                  LevelBadge(risk.level),
                ],
              ),
              const SizedBox(height: 6),
              Text(risk.oneLiner, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.how_to_vote_outlined, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${s.answered}/${s.panel}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 50,
                    child: LinearProgressIndicator(
                      value: s.responseRate,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.forum_outlined, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${s.comments}'),
                  const Spacer(),
                  if (s.panel < minPanel)
                    Tooltip(
                      message: 'Panel under $minPanel experts',
                      child: Icon(Icons.warning_amber_rounded, size: 18, color: cs.tertiary),
                    ),
                ],
              ),
              if (s.answered > 0) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (s.gap != null) _GapLabel(gap: s.gap!, experts: s.expertLikelihood!, acaps: s.acapsLikelihood!),
                    Text('disagree ${(s.disagreement * 100).round()}%', style: t.bodySmall),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Review one risk: results per question with comments + actions underneath
// ===========================================================================

class ModRiskScreen extends StatelessWidget {
  final Risk risk;
  const ModRiskScreen({super.key, required this.risk});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Review · ${risk.id}')),
        body: ListenableBuilder(listenable: appState, builder: (context, _) => ModRiskReview(risk: risk)),
      );
}

enum _CommentView { all, toReview, flagged }

class ModRiskReview extends StatefulWidget {
  final Risk risk;
  const ModRiskReview({super.key, required this.risk});

  @override
  State<ModRiskReview> createState() => _ModRiskReviewState();
}

class _ModRiskReviewState extends State<ModRiskReview> {
  _CommentView _view = _CommentView.all;
  bool _byDispute = false;

  Risk get r => widget.risk;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = r.surveyItems;
    final s = appState.modStats(r);
    final all = appState.commentsOn(r);
    bool keep(Comment c) => switch (_view) {
          _CommentView.all => true,
          _CommentView.toReview => c.needsReview,
          _CommentView.flagged => c.useful || c.usedInRiskId != null,
        };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        RiskHeader(risk: r),
        const SizedBox(height: 12),
        RespondentsCard(risk: r, answered: appState.respondents(r), panelSize: s.panel),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (s.gap != null) _GapLabel(gap: s.gap!, experts: s.expertLikelihood!, acaps: s.acapsLikelihood!),
                  Text('disagree ${(s.disagreement * 100).round()}%', style: t.bodySmall),
                  Text('${s.toReview} of ${s.comments} comments to review', style: t.bodySmall),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _showPublicPreview(context, r),
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Public view'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (v, label) in [
                  (_CommentView.all, 'All · ${all.length}'),
                  (_CommentView.toReview, 'To review · ${s.toReview}'),
                  (_CommentView.flagged, 'Useful / used · ${all.where((c) => c.useful || c.usedInRiskId != null).length}'),
                ])
                  ChoiceChip(label: Text(label), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
                FilterChip(
                  avatar: const Icon(Icons.swap_vert, size: 18),
                  label: Text(_byDispute ? 'Most disputed first' : 'Most agreed first'),
                  selected: _byDispute,
                  onSelected: (v) => setState(() => _byDispute = v),
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < items.length; i++) ...[
          QuestionHeader(number: i + 1, total: items.length, title: items[i].title),
          ItemSummary(risk: r, item: items[i], mine: null),
          _ModCommentList(
            comments: all.where((c) => c.itemId == items[i].id && keep(c)).toList()
              ..sort((a, b) => _byDispute
                  ? b.disagreeIds.length.compareTo(a.disagreeIds.length)
                  : b.agreeIds.length.compareTo(a.agreeIds.length)),
            hiddenByFilter: all.where((c) => c.itemId == items[i].id && !keep(c)).length,
            risk: r,
          ),
          if (i < items.length - 1) const Divider(height: 36),
        ],
      ],
    );
  }
}

class _ModCommentList extends StatelessWidget {
  final List<Comment> comments;
  final int hiddenByFilter;
  final Risk risk;
  const _ModCommentList({required this.comments, required this.hiddenByFilter, required this.risk});

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
              if (hiddenByFilter > 0) Text('  (+$hiddenByFilter hidden by filter)', style: t.bodySmall),
            ],
          ),
          if (comments.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing here.', style: t.bodySmall))
          else
            for (final c in comments) _ModComment(comment: c, risk: risk),
        ],
      ),
    );
  }
}

class _ModComment extends StatelessWidget {
  final Comment comment;
  final Risk risk;
  const _ModComment({required this.comment, required this.risk});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final c = comment;
    final author = appState.expertById(c.authorId);
    final name = author == null ? anonymousName : displayName(author, Viewer.moderator);
    final rc = AppState.riskCountries(risk);
    final pending = c.needsReview;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pending ? cs.error.withAlpha(160) : cs.outlineVariant, width: pending ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name, size: 24),
              const SizedBox(width: 8),
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (author != null) ...[
                const SizedBox(width: 6),
                Pill('L${author.level.number}${author.level == Anonymity.anonymous ? '' : ' · ${author.homeCountry}'}'),
              ],
              const Spacer(),
              if (pending)
                Text('NEW', style: TextStyle(color: cs.error, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(c.text, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showCountriesSheet(context, agreeIds: c.agreeIds, disagreeIds: c.disagreeIds, riskCountries: rc),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.thumb_up_alt_outlined, size: 15, color: cs.onSurfaceVariant),
                Text(' ${c.agreeIds.length}   ', style: t.bodySmall),
                Icon(Icons.thumb_down_alt_outlined, size: 15, color: cs.onSurfaceVariant),
                Text(' ${c.disagreeIds.length}', style: t.bodySmall),
                Text('   · tap for countries', style: t.bodySmall),
              ],
            ),
            ),
          ),
          const Divider(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                avatar: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text('Useful +${Points.usefulComment}'),
                selected: c.useful,
                onSelected: (_) => appState.toggleUseful(c),
              ),
              if (c.usedInRiskId == null)
                ActionChip(
                  avatar: const Icon(Icons.push_pin_outlined, size: 18),
                  label: Text('Use in analysis +${Points.usedComment}'),
                  onPressed: () async {
                    final id = await _pickRisk(context, exclude: risk.id);
                    if (id != null) appState.setUsedIn(c, id);
                  },
                )
              else
                InputChip(
                  avatar: const Icon(Icons.push_pin, size: 18),
                  label: Text('Used in ${c.usedInRiskId}'),
                  selected: true,
                  onDeleted: () => appState.setUsedIn(c, null),
                ),
              if (pending)
                TextButton.icon(
                  onPressed: () => appState.setReviewed(c, true),
                  icon: const Icon(Icons.done, size: 18),
                  label: const Text('Mark reviewed'),
                )
              else if (!c.useful && c.usedInRiskId == null)
                TextButton.icon(
                  onPressed: () => appState.setReviewed(c, false),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Reviewed · undo'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> _pickRisk(BuildContext context, {required String exclude}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RiskPicker(exclude: exclude),
    );

class _RiskPicker extends StatefulWidget {
  final String exclude;
  const _RiskPicker({required this.exclude});

  @override
  State<_RiskPicker> createState() => _RiskPickerState();
}

class _RiskPickerState extends State<_RiskPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = appState.risks
        .where((r) => r.id != widget.exclude && r.isActive)
        .where((r) => q.isEmpty || '${r.id} ${r.title} ${r.country}'.toLowerCase().contains(q))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Used in the analysis of which risk?', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search active risks', isDense: true),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final r in list)
                  ListTile(
                    title: Text(r.oneLiner, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${r.id} · ${r.country}'),
                    trailing: LevelBadge(r.level),
                    onTap: () => Navigator.pop(context, r.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the public may see for this risk: aggregates only, never names or comments.
void _showPublicPreview(BuildContext context, Risk r) {
  final n = appState.respondents(r).length;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final t = Theme.of(context).textTheme;
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Public view', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Aggregates only: no names, no comments, no countries. Hidden below $minPanel respondents.', style: t.bodySmall),
            const SizedBox(height: 12),
            if (n < minPanel)
              InfoBanner(icon: Icons.visibility_off_outlined, text: 'Only $n respondents: nothing is published for this risk.')
            else ...[
              Text('${r.oneLiner}\n$n experts · ACAPS likelihood ${r.acapsLikelihood ?? '-'}/5', style: t.titleSmall),
              for (final it in r.surveyItems) ...[
                const SizedBox(height: 14),
                Text(it.title, style: t.labelLarge),
                Distribution(counts: _likelihoodCounts(appState.answersFor(r, it.id)), acaps: r.acapsLikelihood),
              ],
            ],
          ],
        ),
      );
    },
  );
}

List<int> _likelihoodCounts(List<ItemAnswer> xs) {
  final c = List.filled(5, 0);
  for (final a in xs) {
    c[a.likelihood - 1]++;
  }
  return c;
}

// ===========================================================================
// Panels & experts
// ===========================================================================

enum _PanelSort { smallest, largest, responseRate, name }

class _PanelsTab extends StatefulWidget {
  const _PanelsTab();

  @override
  State<_PanelsTab> createState() => _PanelsTabState();
}

class _PanelsTabState extends State<_PanelsTab> {
  String? _region;
  String _q = '';
  bool _onlyActive = true;
  bool _onlyThin = false;
  _PanelSort _sort = _PanelSort.smallest;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _q.toLowerCase();
    final all = [for (final c in appState.countries) appState.panelStats(c)];
    final rows = all
        .where((p) => _region == null || p.region == _region)
        .where((p) => !_onlyActive || p.activeRisks > 0)
        .where((p) => !_onlyThin || p.experts.length < minPanel)
        .where((p) => q.isEmpty || p.country.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => switch (_sort) {
            _PanelSort.smallest => a.experts.length != b.experts.length
                ? a.experts.length.compareTo(b.experts.length)
                : b.activeRisks.compareTo(a.activeRisks),
            _PanelSort.largest => b.experts.length.compareTo(a.experts.length),
            _PanelSort.responseRate => (a.responseRate ?? 2).compareTo(b.responseRate ?? 2),
            _PanelSort.name => a.country.compareTo(b.country),
          });
    final ready = rows.where((p) => p.experts.length >= minPanel).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Panels', style: t.headlineSmall),
        const SizedBox(height: 4),
        Text('Target: 5-10 experts per country. Below $minPanel, results are not safe to share.', style: t.bodySmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search country', isDense: true),
                  onChanged: (v) => setState(() => _q = v),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  leading: const Icon(Icons.tune),
                  title: const Text('Filters and sort'),
                  subtitle: Text('${_region ?? 'All regions'} · ${switch (_sort) {
                    _PanelSort.smallest => 'smallest first',
                    _PanelSort.largest => 'largest first',
                    _PanelSort.responseRate => 'lowest response',
                    _PanelSort.name => 'A-Z',
                  }}'),
                  children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownMenu<String?>(
                        expandedInsets: EdgeInsets.zero,
                        initialSelection: _region,
                        label: const Text('Region'),
                        textStyle: const TextStyle(fontSize: 13.5),
                        dropdownMenuEntries: [
                          const DropdownMenuEntry(value: null, label: 'All regions'),
                          for (final r in regions.keys) DropdownMenuEntry(value: r, label: r),
                        ],
                        onSelected: (v) => setState(() => _region = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownMenu<_PanelSort>(
                        expandedInsets: EdgeInsets.zero,
                        initialSelection: _sort,
                        label: const Text('Sort by'),
                        textStyle: const TextStyle(fontSize: 13.5),
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(value: _PanelSort.smallest, label: 'Smallest panel first'),
                          DropdownMenuEntry(value: _PanelSort.largest, label: 'Largest panel first'),
                          DropdownMenuEntry(value: _PanelSort.responseRate, label: 'Lowest response rate'),
                          DropdownMenuEntry(value: _PanelSort.name, label: 'Country A-Z'),
                        ],
                        onSelected: (v) {
                          if (v != null) setState(() => _sort = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(label: const Text('With active risks'), selected: _onlyActive, onSelected: (v) => setState(() => _onlyActive = v)),
                    FilterChip(label: Text('Under $minPanel experts'), selected: _onlyThin, onSelected: (v) => setState(() => _onlyThin = v)),
                  ],
                ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text('${rows.length} countries · $ready ready · ${rows.length - ready} need recruiting', style: t.labelLarge),
        ),
        for (final p in rows) _PanelTile(p: p),
      ],
    );
  }
}

class _PanelTile extends StatelessWidget {
  final PanelStats p;
  const _PanelTile({required this.p});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final n = p.experts.length;
    final color = n >= 5 ? cs.primary : (n >= minPanel ? cs.tertiary : cs.error);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(40),
          child: Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        ),
        title: Text(p.country, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p.region} · ${p.activeRisks} active · '
                '${p.experts.isEmpty ? 'no experts' : p.responseRate == null ? 'no surveys' : '${(p.responseRate! * 100).round()}% response'}'),
            const SizedBox(height: 6),
            _PanelBar(n: n),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (p.experts.isEmpty) Text('No experts yet. Share an invite QR code with trusted contacts in ${p.country}.', style: t.bodySmall),
          for (final e in p.experts) _ExpertRow(e: e),
        ],
      ),
    );
  }
}

/// Panel size against the minimum (3) and the target (5-10).
class _PanelBar extends StatelessWidget {
  final int n;
  const _PanelBar({required this.n});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Container(decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4))),
            Container(
              width: box.maxWidth * (n.clamp(0, 10) / 10),
              decoration: BoxDecoration(
                color: n >= 5 ? cs.primary : (n >= minPanel ? cs.tertiary : cs.error),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Positioned(left: box.maxWidth * 0.3 - 1, top: 0, bottom: 0, child: Container(width: 2, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _ExpertRow extends StatelessWidget {
  final Expert e;
  const _ExpertRow({required this.e});

  @override
  Widget build(BuildContext context) {
    final name = displayName(e, Viewer.moderator);
    final st = appState.statsOf(e);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Avatar(name, size: 32),
      title: Text(name),
      subtitle: Text('Level ${e.level.number} · from ${e.homeCountry} · ${appState.responsesOf(e).length} answers'
          '${st.brier == null ? '' : ' · accuracy ${accuracyPct(st.brier!)}%'}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showExpert(context, e),
    );
  }
}

void _showExpert(BuildContext context, Expert e) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final t = Theme.of(context).textTheme;
      final cs = Theme.of(context).colorScheme;
      final name = displayName(e, Viewer.moderator);
      final st = appState.statsOf(e);
      final cm = appState.commentsBy(e);
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Avatar(name, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: t.titleLarge),
                      Text('Level ${e.level.number}: ${e.level.label}', style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill('Panels: ${e.countries.join(', ')}', icon: Icons.place_outlined),
                Pill('${appState.responsesOf(e).length} answers', icon: Icons.how_to_vote_outlined),
                Pill('${cm.length} comments · ${cm.where((c) => c.useful).length} useful', icon: Icons.forum_outlined),
                Pill('${st.points} points', icon: Icons.emoji_events_outlined),
                if (st.brier != null) Pill('accuracy ${accuracyPct(st.brier!)}%', icon: Icons.track_changes),
                if (!e.onRating) const Pill('not in rating', icon: Icons.visibility_off_outlined),
                if (e.hideFromOtherCountries) const Pill('hidden from other countries', icon: Icons.travel_explore),
              ],
            ),
            if (appState.badgesOf(e).isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: [for (final b in appState.badgesOf(e)) AwardIcon(b, size: 26)]),
            ],
            const SectionLabel('Database record'),
            Text(
              e.level == Anonymity.anonymous
                  ? 'Level 3: "real_name" is null. The name is deleted, not hidden.'
                  : 'Exactly what is stored for this expert.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(e.toJson()),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      );
    },
  );
}
