import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models.dart';
import '../store.dart';
import '../download.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';
import 'risk_form.dart';
import 'survey.dart';

/// Moderator workspace, one tab per kind of thing:
///
/// Inbox: only what needs action (countries short of experts, comments to review). Items
///   leave the inbox once handled.
/// Risks: every risk, and the review page for one risk.
/// Experts: every expert, sortable by rating.
class ModeratorShell extends StatefulWidget {
  const ModeratorShell({super.key});

  @override
  State<ModeratorShell> createState() => _ModeratorShellState();
}

const _wideBreakpoint = 900.0;
const _tabNames = ['inbox', 'risks', 'experts'];

class _ModeratorShellState extends State<ModeratorShell> {
  /// Demo links can open a tab directly: ?tab=inbox|risks|experts.
  int _tab = _tabNames.indexOf(Uri.base.queryParameters['tab'] ?? '').clamp(0, _tabNames.length - 1);
  final _filter = RiskFilter();
  String? _selectedRisk = 'R1043';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _openRisk(Risk r) {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    if (wide) {
      setState(() {
        _tab = 1;
        _selectedRisk = r.id;
      });
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModRiskScreen(risk: r)));
    }
  }

  Future<void> _newRisk() async {
    final r = await Navigator.of(context).push<Risk>(MaterialPageRoute(builder: (_) => const RiskFormScreen()));
    if (r == null || !mounted) return;
    final n = appState.panelForRisk(r).length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r.id} published to $n ${n == 1 ? 'expert' : 'experts'}')));
    _openRisk(r);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final inboxN = _Inbox.collect().count;
        Widget inboxIcon(bool selected) {
          final icon = Icon(selected ? Icons.inbox : Icons.inbox_outlined);
          return inboxN == 0 ? icon : Badge(label: Text('$inboxN'), child: icon);
        }

        final dest = [
          (inboxIcon(false), inboxIcon(true), 'Inbox'),
          (const Icon(Icons.fact_check_outlined), const Icon(Icons.fact_check), 'Risks'),
          (const Icon(Icons.groups_2_outlined), const Icon(Icons.groups_2), 'Experts'),
        ];

        final body = IndexedStack(
          index: _tab,
          children: [
            _InboxTab(onOpenRisk: _openRisk),
            _RisksTab(filter: _filter, selectedId: _selectedRisk, onSelect: _openRisk),
            const _ExpertsTab(),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.admin_panel_settings_outlined),
                SizedBox(width: 8),
                Flexible(child: Text('ACAPS moderator', style: TextStyle(fontWeight: FontWeight.w800))),
              ],
            ),
            actions: [
              IconButton(tooltip: 'Invite QR code for any country', onPressed: () => showInviteSheet(context), icon: const Icon(Icons.qr_code_2)),
              IconButton(tooltip: 'Theme and text size', onPressed: () => showDisplaySettings(context), icon: const Icon(Icons.text_fields)),
              IconButton(tooltip: 'Switch user', onPressed: appState.signOut, icon: const Icon(Icons.logout)),
            ],
          ),
          floatingActionButton: _tab == 1
              ? FloatingActionButton.extended(onPressed: _newRisk, icon: const Icon(Icons.add), label: const Text('New risk'))
              : null,
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tab,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() => _tab = i),
                      destinations: [
                        for (final d in dest) NavigationRailDestination(icon: d.$1, selectedIcon: d.$2, label: Text(d.$3)),
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
                  destinations: [for (final d in dest) NavigationDestination(icon: d.$1, selectedIcon: d.$2, label: d.$3)],
                ),
        );
      },
    );
  }
}

// ===========================================================================
// Inbox: only what needs action
// ===========================================================================

typedef _PanelAlert = ({String country, int n, int active});

class _Inbox {
  /// Countries with active risks and 1-2 experts: answers exist, but group
  /// results could reveal who gave them. Most urgent.
  final List<_PanelAlert> belowMin;

  /// Countries with active risks and nobody on the panel: a coverage gap.
  final List<_PanelAlert> empty;

  /// Risks with comments nobody has reviewed yet, most first.
  final List<(Risk, int)> toReview;

  const _Inbox(this.belowMin, this.empty, this.toReview);

  /// Badge count: actionable items. Empty panels are a backlog, not counted.
  int get count => belowMin.length + toReview.length;

  static _Inbox collect() {
    final thin = appState.thinPanels;
    final pending = <String, int>{};
    for (final c in appState.comments.where((c) => c.needsReview)) {
      pending[c.riskId] = (pending[c.riskId] ?? 0) + 1;
    }
    final toReview = [
      for (final e in pending.entries)
        if (appState.byId(e.key) case final r?) (r, e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    int byActive(_PanelAlert a, _PanelAlert b) => b.active != a.active ? b.active.compareTo(a.active) : a.country.compareTo(b.country);
    return _Inbox(
      thin.where((p) => p.n > 0).toList()..sort(byActive),
      thin.where((p) => p.n == 0).toList()..sort(byActive),
      toReview,
    );
  }
}

class _InboxTab extends StatelessWidget {
  final ValueChanged<Risk> onOpenRisk;
  const _InboxTab({required this.onOpenRisk});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final inbox = _Inbox.collect();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('Inbox', style: t.headlineSmall),
        const SizedBox(height: 4),
        Text('What needs you. Items leave the inbox once handled.', style: t.bodySmall),
        if (inbox.count == 0 && inbox.empty.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              children: [
                Icon(Icons.task_alt, size: 48, color: cs.primary),
                const SizedBox(height: 8),
                Text('All clear.', style: t.titleMedium),
              ],
            ),
          ),

        // 1. Countries short of experts: privacy first.
        if (inbox.belowMin.isNotEmpty) ...[
          _SectionHeader(icon: Icons.warning_amber_rounded, color: cs.error, title: 'Countries with fewer than $minPanel experts', count: inbox.belowMin.length),
          Text('These countries have active risks, but so few experts that group results could reveal who answered. Invite more.',
              style: t.bodySmall),
          const SizedBox(height: 6),
          for (final p in inbox.belowMin) _PanelAlertTile(p: p),
        ],

        // 2. Comments to review, one line per risk.
        if (inbox.toReview.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.forum_outlined,
            title: 'Comments to review',
            count: inbox.toReview.fold<int>(0, (s, x) => s + x.$2),
          ),
          for (final (r, n) in inbox.toReview)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                onTap: () => onOpenRisk(r),
                title: Text(r.oneLiner, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${r.id} · ${r.country}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CountPill('$n new', color: cs.error),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
        ],

        // 3. Countries with no experts at all: backlog, collapsed.
        if (inbox.empty.isNotEmpty) ...[
          const SizedBox(height: 18),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: Icon(Icons.person_search_outlined, color: cs.onSurfaceVariant),
              title: Text('No experts yet · ${inbox.empty.length} countries'),
              subtitle: const Text('These countries have active risks but nobody to ask. Shown: active risks per country. Tap one to invite.'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in inbox.empty)
                      ActionChip(
                        avatar: const Icon(Icons.person_add_alt, size: 18),
                        label: Text('${p.country} · ${p.active} ${p.active == 1 ? 'risk' : 'risks'}'),
                        onPressed: () => showInviteSheet(context, p.country),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PanelAlertTile extends StatelessWidget {
  final _PanelAlert p;
  const _PanelAlertTile({required this.p});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.error.withAlpha(120))),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.error.withAlpha(36),
          child: Text('${p.n}', style: TextStyle(color: cs.error, fontWeight: FontWeight.w900)),
        ),
        title: Text(p.country, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${p.n} of $minPanel experts · ${p.active} active ${p.active == 1 ? 'risk' : 'risks'}'),
        trailing: FilledButton.tonalIcon(
          // The app theme makes filled buttons full width; a ListTile trailing needs a finite size.
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => showInviteSheet(context, p.country),
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Invite'),
        ),
        onTap: () => showInviteSheet(context, p.country),
      ),
    );
  }
}

/// The invite QR code ACAPS shares with trusted contacts in one country.
/// Without [country], the moderator picks one in the sheet.
void showInviteSheet(BuildContext context, [String? country]) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _InviteSheet(country: country),
      ),
    ),
  );
}

/// Link a scanned code opens: this app with ?invite=<code>.
String inviteLink(String code) {
  final b = Uri.base;
  return Uri(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null, path: b.path, queryParameters: {'invite': code})
      .toString();
}

/// PNG of the QR code on white, ready to print.
Future<Uint8List> _qrPng(String data) async {
  const size = 1024.0, pad = 64.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = Colors.white);
  canvas.translate(pad, pad);
  QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
  ).paint(canvas, const Size(size - 2 * pad, size - 2 * pad));
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

class _InviteSheet extends StatefulWidget {
  final String? country;
  const _InviteSheet({this.country});

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  late String? _country = widget.country;

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = _country;
    final code = c == null ? null : inviteCodeFor(c);
    final n = c == null ? 0 : appState.panelFor(c).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 48),
              Expanded(child: Text('Invite experts', textAlign: TextAlign.center, style: t.titleLarge)),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            expandedInsets: EdgeInsets.zero,
            initialSelection: c,
            menuHeight: 320,
            label: const Text('Country'),
            leadingIcon: const Icon(Icons.place_outlined),
            dropdownMenuEntries: [for (final x in appState.countries) DropdownMenuEntry(value: x, label: x)],
            onSelected: (v) => setState(() => _country = v),
          ),
          if (c == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text('Pick a country to get its invite QR code.', style: t.bodySmall),
            )
          else ...[
            const SizedBox(height: 6),
            Text('$n ${n == 1 ? 'expert' : 'experts'} in $c now · minimum $minPanel · target 5-10', style: t.bodySmall),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: inviteLink(code!), size: 200, backgroundColor: Colors.white, padding: EdgeInsets.zero),
            ),
            const SizedBox(height: 10),
            SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 6),
            Text('Share it only with people you trust. Whoever scans it joins as an expert for $c.',
                textAlign: TextAlign.center, style: t.bodySmall),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (canDownload)
                  OutlinedButton.icon(
                    onPressed: () async => downloadBytes('invite-${code.toLowerCase()}.png', await _qrPng(inviteLink(code)), 'image/png'),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download QR (PNG)'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _copy(inviteLink(code), 'Invite link for $c'),
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Copy link'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copy(code, 'Invite code for $c'),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy code'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final Color? color;
  const _SectionHeader({required this.icon, required this.title, this.count, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(count == null ? title : '$title · $count', style: Theme.of(context).textTheme.titleMedium)),
          ],
        ),
      );
}

class _CountPill extends StatelessWidget {
  final String text;
  final Color color;
  const _CountPill(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onError, fontSize: 11.5, fontWeight: FontWeight.w800)),
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
        Flexible(
          child: Text('likelihood: experts ${experts.toStringAsFixed(1)} vs ACAPS $acaps',
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ],
    );
  }
}

// ===========================================================================
// Risks: search + status on screen, everything else in a filter sheet
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
    clearSheet();
    status = RiskStatus.active;
  }

  /// Resets what lives in the filter sheet (not search, not status).
  void clearSheet() {
    region = null;
    country = null;
    sort = RiskSort.toReview;
    onlyToReview = false;
    minDisagreement = 0;
  }

  /// Filters set in the sheet (sort is not a filter).
  int get sheetCount => (region == null ? 0 : 1) + (country == null ? 0 : 1) + (onlyToReview ? 1 : 0) + (minDisagreement > 0 ? 1 : 0);

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
          builder: (context, _) => _RiskList(filter: filter, selectedId: wide ? selectedId : null, onSelect: onSelect),
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

class _RiskList extends StatefulWidget {
  final RiskFilter filter;
  final String? selectedId;
  final ValueChanged<Risk> onSelect;
  const _RiskList({required this.filter, required this.selectedId, required this.onSelect});

  @override
  State<_RiskList> createState() => _RiskListState();
}

class _RiskListState extends State<_RiskList> {
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
    if (_search.text != f.query) _search.text = f.query;
    final rows = f.apply(appState.risks);
    final n = f.sheetCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search ID, title or country', isDense: true),
                onChanged: (v) => f.update((x) => x.query = v),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: n > 0,
              label: Text('$n'),
              child: IconButton.filledTonal(
                tooltip: 'Filter and sort',
                onPressed: () => _showRiskFilterSheet(context, f),
                icon: const Icon(Icons.tune),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Text('${rows.length} ${rows.length == 1 ? 'risk' : 'risks'} · ${f.sort.label.toLowerCase()}',
                    style: t.labelLarge, overflow: TextOverflow.ellipsis),
              ),
              if (n > 0 || f.query.isNotEmpty)
                TextButton(onPressed: () => f.update((x) => x.clear()), child: const Text('Clear')),
            ],
          ),
        ),
        if (rows.isEmpty) const _Empty('No risks match.'),
        for (final (r, s) in rows) _ModRiskTile(risk: r, s: s, selected: r.id == widget.selectedId, onTap: () => widget.onSelect(r)),
      ],
    );
  }
}

void _showRiskFilterSheet(BuildContext context, RiskFilter f) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: f,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final countries = (f.region == null ? appState.countries : appState.countries.where((c) => regionOf(c) == f.region)).toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Filter and sort', style: t.titleLarge)),
                  TextButton(onPressed: () => f.update((x) => x.clearSheet()), child: const Text('Reset')),
                ],
              ),
              const SectionLabel('Sort'),
              DropdownMenu<RiskSort>(
                key: ValueKey('sort-${f.sort}'),
                expandedInsets: EdgeInsets.zero,
                initialSelection: f.sort,
                leadingIcon: const Icon(Icons.sort),
                dropdownMenuEntries: [for (final s in RiskSort.values) DropdownMenuEntry(value: s, label: s.label)],
                onSelected: (v) {
                  if (v != null) f.update((x) => x.sort = v);
                },
              ),
              const SectionLabel('Where'),
              DropdownMenu<String?>(
                key: ValueKey('region-${f.region}'),
                expandedInsets: EdgeInsets.zero,
                initialSelection: f.region,
                label: const Text('Region'),
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: null, label: 'All regions'),
                  for (final r in regions.keys) DropdownMenuEntry(value: r, label: r),
                ],
                onSelected: (v) => f.update((x) {
                  x.region = v;
                  if (v != null && x.country != null && regionOf(x.country!) != v) x.country = null;
                }),
              ),
              const SizedBox(height: 10),
              DropdownMenu<String?>(
                key: ValueKey('country-${f.country}-${f.region}'),
                expandedInsets: EdgeInsets.zero,
                initialSelection: f.country,
                menuHeight: 320,
                label: const Text('Country'),
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: null, label: 'All countries'),
                  for (final c in countries) DropdownMenuEntry(value: c, label: c),
                ],
                onSelected: (v) => f.update((x) => x.country = v),
              ),
              const SectionLabel('Show only'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: f.onlyToReview,
                onChanged: (v) => f.update((x) => x.onlyToReview = v),
                title: const Text('Risks with comments to review'),
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
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ],
          ),
        );
      },
    ),
  );
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
                  if (s.toReview > 0) ...[_CountPill('${s.toReview} new', color: cs.error), const SizedBox(width: 6)],
                  LevelBadge(risk.level),
                ],
              ),
              const SizedBox(height: 6),
              Text(risk.oneLiner, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${s.answered}/${s.panel} answered', style: t.bodySmall),
                  if (s.gap != null) _GapLabel(gap: s.gap!, experts: s.expertLikelihood!, acaps: s.acapsLikelihood!),
                  if (s.panel < minPanel)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
                        const SizedBox(width: 3),
                        Text('too few experts', style: TextStyle(color: cs.error, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ],
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

// ===========================================================================
// Review one risk: results per question with comments + actions underneath
// ===========================================================================

class ModRiskScreen extends StatelessWidget {
  final Risk risk;
  const ModRiskScreen({super.key, required this.risk});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Review · ${risk.id}')),
        body: ListenableBuilder(
          listenable: appState,
          builder: (context, _) => ModRiskReview(risk: appState.byId(risk.id) ?? risk),
        ),
      );
}

class ModRiskReview extends StatefulWidget {
  final Risk risk;
  const ModRiskReview({super.key, required this.risk});

  @override
  State<ModRiskReview> createState() => _ModRiskReviewState();
}

class _ModRiskReviewState extends State<ModRiskReview> {
  /// Opens on "to review" when there is something to review.
  late bool _onlyNew = appState.modStats(widget.risk).toReview > 0;

  Risk get r => widget.risk;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final items = r.surveyItems;
    final s = appState.modStats(r);
    final all = appState.commentsOn(r);
    final thin = [for (final c in AppState.riskCountries(r)) (c, appState.panelFor(c).length)].where((x) => x.$2 < minPanel).toList();
    bool keep(Comment c) => !_onlyNew || c.needsReview;
    int order(Comment a, Comment b) => a.needsReview != b.needsReview
        ? (a.needsReview ? -1 : 1)
        : b.agreeIds.length.compareTo(a.agreeIds.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        RiskHeader(risk: r),
        if (r.custom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Pill('Added in the app', icon: Icons.edit_note),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RiskFormScreen(initial: r))),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => _confirmDelete(context, r),
                icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                label: Text('Delete', style: TextStyle(color: cs.error)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (thin.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              color: cs.error.withAlpha(24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.error.withAlpha(110)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fewer than $minPanel experts in ${thin.map((x) => '${x.$1} (${x.$2})').join(', ')}. '
                    'Results there could reveal who answered.',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                TextButton(onPressed: () => showInviteSheet(context, thin.first.$1), child: const Text('Invite')),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
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
                  if (s.answered > 0) Text('disagree with ACAPS ${(s.disagreement * 100).round()}%', style: t.bodySmall),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _showPublicPreview(context, r),
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Publish'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (all.isNotEmpty)
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text('To review · ${s.toReview}')),
              ButtonSegment(value: false, label: Text('All comments · ${all.length}')),
            ],
            selected: {_onlyNew},
            onSelectionChanged: (v) => setState(() => _onlyNew = v.first),
          ),
        for (var i = 0; i < items.length; i++) ...[
          QuestionHeader(number: i + 1, total: items.length, title: items[i].title),
          ItemSummary(risk: r, item: items[i], mine: null),
          _ModCommentList(
            comments: all.where((c) => c.itemId == items[i].id && keep(c)).toList()..sort(order),
            hiddenByFilter: all.where((c) => c.itemId == items[i].id && !keep(c)).length,
            risk: r,
          ),
          if (i < items.length - 1) const Divider(height: 36),
        ],
      ],
    );
  }
}

Future<void> _confirmDelete(BuildContext context, Risk r) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${r.id}?'),
      content: const Text('The risk, its answers and its comments are removed. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  Navigator.of(context).maybePop();
  appState.deleteRisk(r);
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
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.forum_outlined, size: 16, color: cs.primary),
              Text('What ACAPS is missing · ${comments.length}', style: t.labelLarge),
              if (hiddenByFilter > 0) Text('(+$hiddenByFilter already reviewed)', style: t.bodySmall),
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
          Tooltip(
            message: 'Agree: ${describeSplit(appState.expertsByIds(c.agreeIds), rc)}\n'
                'Disagree: ${describeSplit(appState.expertsByIds(c.disagreeIds), rc)}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.thumb_up_alt_outlined, size: 15, color: cs.onSurfaceVariant),
                Text(' ${c.agreeIds.length}   ', style: t.bodySmall),
                Icon(Icons.thumb_down_alt_outlined, size: 15, color: cs.onSurfaceVariant),
                Text(' ${c.disagreeIds.length}', style: t.bodySmall),
                
              ],
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

/// What the public may see for this risk, and the export for the website:
/// aggregates only, plus the names of experts who agreed to be credited.
void _showPublicPreview(BuildContext context, Risk r) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PublishSheet(risk: r),
  );
}

class _PublishSheet extends StatefulWidget {
  final Risk risk;
  const _PublishSheet({required this.risk});

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  bool _credits = true;

  void _export(List<Risk> rs, String name) {
    final json = appState.publicViewJson(rs, credits: _credits);
    if (canDownload) {
      downloadText(name, json);
    } else {
      _copy(json);
    }
  }

  void _copy(String json) {
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copied')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = widget.risk;
    final n = appState.respondents(r).length;
    final all = appState.publishableRisks;
    final credited = appState.creditsFor(r);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Publish · ${r.id}', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('Aggregates only: no comments, no respondent countries, no names next to answers. '
              'Results are hidden below $minPanel respondents.', style: t.bodySmall),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _credits,
            onChanged: (v) => setState(() => _credits = v),
            title: const Text('Credit experts who agreed'),
            subtitle: const Text('Each expert chooses per risk: real name, pseudonym or anonymous. The default comes from their profile.'),
          ),
          if (_credits && n >= minPanel)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest.withAlpha(120), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Contributors', style: t.labelLarge),
                  const SizedBox(height: 6),
                  if (credited.isEmpty)
                    Text('Nobody asked to be named.', style: t.bodySmall)
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in credited)
                          Pill(c.name, icon: c.as == Credit.realName ? Icons.person_outline : Icons.masks_outlined),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text('+ ${n - credited.length} anonymous', style: t.bodySmall),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _export([r], 'public-view-${r.id.toLowerCase()}.json'),
                icon: Icon(canDownload ? Icons.download : Icons.copy, size: 18),
                label: const Text('This risk (JSON)'),
              ),
              OutlinedButton.icon(
                onPressed: all.isEmpty ? null : () => _export(all, 'public-view-all.json'),
                icon: Icon(canDownload ? Icons.download : Icons.copy, size: 18),
                label: Text('All publishable · ${all.length} (JSON)'),
              ),
              TextButton.icon(
                onPressed: () => _copy(appState.publicViewJson([r], credits: _credits)),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy JSON'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (n < minPanel)
            InfoBanner(icon: Icons.visibility_off_outlined, text: 'Only $n respondents: no results or names are published for this risk. The export contains the ACAPS rating only.')
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
  }
}

List<int> _likelihoodCounts(List<ItemAnswer> xs) {
  final c = List.filled(5, 0);
  for (final a in xs) {
    c[a.likelihood - 1]++;
  }
  return c;
}

// ===========================================================================
// Experts: one directory, sortable by rating
// ===========================================================================

enum _ExpertSort { points, accuracy, answers, name }

extension on _ExpertSort {
  String get label => switch (this) {
        _ExpertSort.points => 'Points',
        _ExpertSort.accuracy => 'Accuracy',
        _ExpertSort.answers => 'Answers',
        _ExpertSort.name => 'Name',
      };
}

class _ExpertsTab extends StatefulWidget {
  const _ExpertsTab();

  @override
  State<_ExpertsTab> createState() => _ExpertsTabState();
}

class _ExpertsTabState extends State<_ExpertsTab> {
  String _q = '';
  String? _country;
  _ExpertSort _sort = _ExpertSort.points;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final q = _q.toLowerCase();
    final rows = appState.experts
        .where((e) => _country == null || e.inPanel(_country!))
        .where((e) => q.isEmpty || '${displayName(e, Viewer.moderator)} ${e.pseudonym} ${e.homeCountry}'.toLowerCase().contains(q))
        .map((e) => (e, appState.statsOf(e), appState.responsesOf(e).length))
        .toList()
      ..sort((a, b) => switch (_sort) {
            _ExpertSort.points => b.$2.points.compareTo(a.$2.points),
            _ExpertSort.accuracy => (a.$2.brier ?? 2).compareTo(b.$2.brier ?? 2),
            _ExpertSort.answers => b.$3.compareTo(a.$3),
            _ExpertSort.name => displayName(a.$1, Viewer.moderator).compareTo(displayName(b.$1, Viewer.moderator)),
          });
    final panelN = _country == null ? null : appState.panelFor(_country!).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            Expanded(child: Text('Experts', style: t.headlineSmall)),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(appBar: AppBar(title: const Text('Rating as experts see it')), body: const RatingTab()),
              )),
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: const Text('Leaderboard'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, pseudonym or country', isDense: true),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownMenu<String?>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: _country,
                menuHeight: 320,
                label: const Text('Country'),
                textStyle: const TextStyle(fontSize: 13.5),
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: null, label: 'All countries'),
                  for (final c in appState.countries) DropdownMenuEntry(value: c, label: c),
                ],
                onSelected: (v) => setState(() => _country = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownMenu<_ExpertSort>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: _sort,
                label: const Text('Sort by'),
                textStyle: const TextStyle(fontSize: 13.5),
                dropdownMenuEntries: [for (final s in _ExpertSort.values) DropdownMenuEntry(value: s, label: s.label)],
                onSelected: (v) {
                  if (v != null) setState(() => _sort = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (_country != null) ...[
              Icon(panelN! < minPanel ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  size: 18, color: panelN < minPanel ? cs.error : cs.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('$_country: $panelN ${panelN == 1 ? 'expert' : 'experts'} · target 5-10, minimum $minPanel', style: t.bodySmall)),
            ] else
              const Spacer(),
            TextButton.icon(
              onPressed: () => showInviteSheet(context, _country),
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('Invite experts'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text('${rows.length} ${rows.length == 1 ? 'expert' : 'experts'}', style: t.labelLarge),
        ),
        if (rows.isEmpty) const _Empty('Nobody here yet.'),
        for (final (e, st, answers) in rows)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Avatar(displayName(e, Viewer.moderator), size: 36),
              title: Text(displayName(e, Viewer.moderator)),
              subtitle: Text('L${e.level.number} · ${e.countries.join(', ')} · $answers answers'
                  '${st.brier == null ? '' : ' · accuracy ${accuracyPct(st.brier!)}%'}'),
              trailing: Text('${st.points}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              onTap: () => _showExpert(context, e),
            ),
          ),
      ],
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
                Pill('Countries: ${e.countries.join(', ')}', icon: Icons.place_outlined),
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
