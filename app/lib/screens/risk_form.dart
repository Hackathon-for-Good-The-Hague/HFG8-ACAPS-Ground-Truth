import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';

const _riskTypes = [
  'New emerging risk',
  'Marked deterioration in an existing crisis',
  'Future impact of a hazard which has already taken place',
];
const _riskLevels = ['Low', 'Medium', 'High'];
const _maxTriggers = 3;

/// Moderator form to add a risk, or edit one that was added in the app.
/// Pops with the saved [Risk], or null when cancelled.
class RiskFormScreen extends StatefulWidget {
  final Risk? initial;
  const RiskFormScreen({super.key, this.initial});

  @override
  State<RiskFormScreen> createState() => _RiskFormScreenState();
}

class _Trig {
  final String? id;
  final TextEditingController title;
  final TextEditingController desc;
  _Trig({this.id, String title = '', String desc = ''})
      : title = TextEditingController(text: title),
        desc = TextEditingController(text: desc);
  void dispose() {
    title.dispose();
    desc.dispose();
  }
}

class _RiskFormScreenState extends State<RiskFormScreen> {
  late final Risk? r0 = widget.initial;
  late final _title = TextEditingController(text: r0?.title);
  late final _rationale = TextEditingController(text: r0?.rationale);
  late final _exposure = TextEditingController(text: r0?.exposure);
  late final _needs = TextEditingController(text: r0?.needs);
  late final List<String> _countries = r0 == null ? [] : AppState.riskCountries(r0!);
  late String _type = _riskTypes.contains(r0?.type) ? r0!.type : _riskTypes.first;
  late int? _prob = r0?.probabilityIdx;
  late int? _impact = r0?.impact;
  late String? _level = _riskLevels.contains(r0?.level) ? r0!.level : null;
  late final List<_Trig> _triggers = [
    for (final t in r0?.triggers ?? const <Trigger>[]) _Trig(id: t.id, title: t.title, desc: t.description),
  ];
  bool _tried = false;
  TextEditingController? _countryField;

  @override
  void dispose() {
    for (final c in [_title, _rationale, _exposure, _needs]) {
      c.dispose();
    }
    for (final t in _triggers) {
      t.dispose();
    }
    super.dispose();
  }

  List<String> get _allCountries => {...appState.countries, for (final cs in regions.values) ...cs}.toList()..sort();

  List<String> get _missing => [
        if (_title.text.trim().isEmpty) 'title',
        if (_countries.isEmpty) 'country',
        if (_prob == null) 'probability',
        if (_impact == null) 'impact',
        if (_level == null) 'risk level',
        if (_rationale.text.trim().isEmpty) 'rationale',
        if (_triggers.any((t) => t.title.text.trim().isEmpty)) 'trigger title',
      ];

  void _save() {
    setState(() => _tried = true);
    if (_missing.isNotEmpty) return;
    final id = r0?.id ?? appState.nextRiskId();
    final risk = Risk(
      custom: true,
      id: id,
      title: _title.text.trim(),
      type: _type,
      country: _countries.join(', '),
      rationale: _rationale.text.trim(),
      probabilityIdx: _prob,
      impact: _impact,
      level: _level!,
      trend: r0?.trend ?? '',
      status: r0?.status ?? 'Active',
      exposure: _exposure.text.trim(),
      needs: _needs.text.trim(),
      materialisation: r0?.materialisation ?? '',
      triggers: [
        for (var i = 0; i < _triggers.length; i++)
          Trigger(
            id: _triggers[i].id ?? '$id - T${i + 1}',
            title: _triggers[i].title.text.trim(),
            description: _triggers[i].desc.text.trim(),
          ),
      ],
    );
    appState.saveRisk(risk);
    Navigator.pop(context, risk);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final reach = appState.experts.where((e) => _countries.any(e.inPanel)).length;
    final editing = r0 != null;

    Widget err(bool bad) => !_tried || !bad
        ? const SizedBox()
        : Padding(padding: const EdgeInsets.only(top: 4), child: Text('Required', style: TextStyle(color: cs.error, fontSize: 12.5)));

    Widget choices<T>(List<T> values, T? selected, String Function(T) label, ValueChanged<T> onPick) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(label: Text(label(v)), selected: v == selected, onSelected: (_) => setState(() => onPick(v))),
          ],
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit ${r0!.id}' : 'New risk'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(onPressed: _save, child: Text(editing ? 'Save' : 'Publish')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Risk'),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Flooding cuts road access in Jonglei'),
                    onChanged: (_) => setState(() {}),
                  ),
                  err(_title.text.trim().isEmpty),
                  const SizedBox(height: 12),
                  DropdownMenu<String>(
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: _type,
                    label: const Text('Type'),
                    dropdownMenuEntries: [for (final x in _riskTypes) DropdownMenuEntry(value: x, label: x)],
                    onSelected: (v) {
                      if (v != null) setState(() => _type = v);
                    },
                  ),

                  const SectionLabel('Country'),
                  if (_countries.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in _countries) InputChip(label: Text(c), onDeleted: () => setState(() => _countries.remove(c))),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Autocomplete<String>(
                    optionsBuilder: (v) {
                      final q = v.text.toLowerCase();
                      return _allCountries.where((c) => !_countries.contains(c) && c.toLowerCase().contains(q));
                    },
                    onSelected: (c) {
                      setState(() => _countries.add(c));
                      _countryField?.clear();
                    },
                    fieldViewBuilder: (context, controller, focus, onSubmit) {
                      _countryField = controller;
                      return TextField(
                        controller: controller,
                        focusNode: focus,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.place_outlined),
                          hintText: _countries.isEmpty ? 'Add a country' : 'Add another country',
                        ),
                      );
                    },
                  ),
                  err(_countries.isEmpty),
                  if (_countries.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(reach < minPanel ? Icons.warning_amber_rounded : Icons.groups_2_outlined,
                            size: 18, color: reach < minPanel ? cs.error : cs.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reach < minPanel
                                ? 'Only $reach ${reach == 1 ? 'expert' : 'experts'} in these countries. Results stay hidden below $minPanel: invite more in Inbox.'
                                : '$reach experts in these countries will be asked.',
                            style: t.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SectionLabel('ACAPS rating'),
                  Text('Probability', style: t.labelLarge),
                  const SizedBox(height: 6),
                  choices<int>(List.generate(5, (i) => i), _prob, (i) => levelLabels[i], (v) => _prob = v),
                  err(_prob == null),
                  const SizedBox(height: 14),
                  Text('Impact (1-5)', style: t.labelLarge),
                  const SizedBox(height: 6),
                  choices<int>(const [1, 2, 3, 4, 5], _impact, (i) => '$i', (v) => _impact = v),
                  err(_impact == null),
                  const SizedBox(height: 14),
                  Text('Risk level', style: t.labelLarge),
                  const SizedBox(height: 6),
                  choices<String>(_riskLevels, _level, (s) => s, (v) => _level = v),
                  err(_level == null),

                  const SectionLabel('Rationale'),
                  TextField(
                    controller: _rationale,
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(hintText: 'Why ACAPS thinks this may happen in the next six months.'),
                    onChanged: (_) => setState(() {}),
                  ),
                  err(_rationale.text.trim().isEmpty),

                  SectionLabel('Triggers · ${_triggers.length} of $_maxTriggers'),
                  Text('Experts answer one screen per trigger. Without triggers they rate the risk as a whole.', style: t.bodySmall),
                  for (var i = 0; i < _triggers.length; i++)
                    Card(
                      margin: const EdgeInsets.only(top: 10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text('Trigger ${i + 1}', style: t.labelLarge)),
                                IconButton(
                                  tooltip: 'Remove trigger',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => setState(() => _triggers.removeAt(i).dispose()),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: _triggers[i].title,
                                    decoration: const InputDecoration(labelText: 'Title', isDense: true),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                  err(_triggers[i].title.text.trim().isEmpty),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _triggers[i].desc,
                                    minLines: 2,
                                    maxLines: 6,
                                    decoration: const InputDecoration(labelText: 'Description (optional)', isDense: true),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_triggers.length < _maxTriggers)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton.icon(
                          onPressed: () => setState(() => _triggers.add(_Trig())),
                          icon: const Icon(Icons.add),
                          label: const Text('Add trigger'),
                        ),
                      ),
                    ),

                  const SectionLabel('More (optional)'),
                  TextField(controller: _exposure, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Expected exposure')),
                  const SizedBox(height: 10),
                  TextField(controller: _needs, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Expected priority needs')),

                  const SizedBox(height: 24),
                  if (_tried && _missing.isNotEmpty) ...[
                    InfoBanner(icon: Icons.error_outline, color: cs.error, text: 'Still missing: ${_missing.toSet().join(', ')}.'),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed: _save,
                    icon: Icon(editing ? Icons.save_outlined : Icons.send_outlined),
                    label: Text(editing ? 'Save changes' : 'Publish to experts'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
