import 'package:flutter/material.dart';

import 'models.dart';
import 'screens/survey.dart';
import 'store.dart';
import 'theme.dart';

/// Small uppercase section label.
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.only(top: 24, bottom: 10)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class LevelBadge extends StatelessWidget {
  final String level;
  const LevelBadge(this.level, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = levelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            level.isEmpty ? 'Unrated' : '$level risk',
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final bool strong;
  final IconData? icon;
  const Pill(this.text, {super.key, this.strong = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = strong ? cs.onPrimary : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/// Initials avatar with a colour derived from the name; anonymous gets a mask.
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool faded;
  final bool ring;

  const Avatar(this.name, {super.key, this.size = 36, this.faded = false, this.ring = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final anon = name == anonymousName || name.contains('anonymous');
    final hue = (stableHash(name) % 360).toDouble();
    final color = anon
        ? cs.onSurfaceVariant
        : HSLColor.fromAHSL(1, hue, 0.38, 0.45).toColor();
    final initials = name
        .split(RegExp(r'[\s\-_]+'))
        .where((p) => p.isNotEmpty && !RegExp(r'^\d+$').hasMatch(p))
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: faded ? Colors.transparent : color.withAlpha(anon ? 50 : 230),
        border: Border.all(
          color: ring ? cs.primary : (faded ? cs.outlineVariant : Colors.transparent),
          width: ring ? 2.5 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: anon
          ? Icon(Icons.visibility_off_outlined,
              size: size * 0.48, color: faded ? cs.outlineVariant : cs.onSurface)
          : Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                color: faded ? cs.outlineVariant : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.36,
              ),
            ),
    );
  }
}

/// Selectable option card (used for anonymity levels).
class OptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const OptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: selected ? cs.primary.withAlpha(22) : cs.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.check_circle, color: cs.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData anonymityIcon(Anonymity a) => switch (a) {
      Anonymity.knownToAcaps => Icons.badge_outlined,
      Anonymity.pseudonymous => Icons.theater_comedy_outlined,
      Anonymity.anonymous => Icons.visibility_off_outlined,
    };

/// A risk in a list: tap to open its survey.
class RiskTile extends StatelessWidget {
  final Risk risk;
  final String? trailing;

  const RiskTile({super.key, required this.risk, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = appState.me;
    final done = me != null && appState.responseOf(me, risk) != null;
    final stripe = risk.isResolved ? cs.tertiary : levelColor(risk.level);
    final n = risk.surveyItems.length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SurveyScreen(risk: risk, start: done ? SurveyStart.summary : SurveyStart.intro),
          )),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: stripe),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${risk.id}  ·  ${risk.country.toUpperCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (risk.isResolved) const Pill('Archive', icon: Icons.history_edu),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          risk.oneLiner,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            LevelBadge(risk.level),
                            const Spacer(),
                            done
                                ? Icon(Icons.check_circle, color: cs.primary, size: 22)
                                : Text(trailing ?? '$n ${n == 1 ? 'question' : 'questions'} · 2 min',
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Coloured risk header (code, country, one-liner, ACAPS rating). Also used for
/// the "forecast matured" block, so both look like the same risk card.
class RiskHeader extends StatelessWidget {
  final Risk risk;
  final Widget? footer;
  const RiskHeader({super.key, required this.risk, this.footer});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = risk.probabilityIdx;
    return Container(
      decoration: BoxDecoration(
        color: levelColor(risk.level).withAlpha(dark ? 45 : 26),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${risk.id}  ·  ${risk.country.toUpperCase()}',
                  style: TextStyle(fontSize: 11.5, letterSpacing: 0.9, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
                ),
              ),
              LevelBadge(risk.level),
            ],
          ),
          const SizedBox(height: 8),
          Text(risk.oneLiner, style: t.titleMedium),
          const SizedBox(height: 10),
          Text(
            'ACAPS: ${p == null ? 'unrated' : '${levelLabels[p].toLowerCase()} probability'}'
            '${risk.impact == null ? '' : ' · impact ${risk.impact}/5'}',
            style: t.bodySmall,
          ),
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
  }
}

/// Fade + slide-up when first built.
class Reveal extends StatelessWidget {
  final Widget child;
  final int delayMs;
  const Reveal({super.key, required this.child, this.delayMs = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + delayMs),
      curve: Interval(delayMs / (380 + delayMs), 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: child),
      ),
      child: child,
    );
  }
}

class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const InfoBanner({super.key, required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withAlpha(30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}

/// Theme and text size controls.
class DisplaySettings extends StatelessWidget {
  const DisplaySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: t.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final th in AppTheme.values)
                  ChoiceChip(
                    avatar: Icon(switch (th) {
                      AppTheme.system => Icons.brightness_auto_outlined,
                      AppTheme.light => Icons.light_mode_outlined,
                      AppTheme.dark => Icons.dark_mode_outlined,
                      AppTheme.contrast => Icons.contrast,
                    }, size: 18),
                    label: Text(th.label),
                    selected: appState.theme == th,
                    onSelected: (_) => appState.setTheme(th),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Text size', style: t.labelLarge)),
                if (appState.textScale != 1.0)
                  TextButton(onPressed: () => appState.setTextScale(1.0), child: const Text('Reset to 100%')),
              ],
            ),
            Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: appState.textScale.clamp(minTextScale, maxTextScale),
                    min: minTextScale,
                    max: maxTextScale,
                    divisions: ((maxTextScale - minTextScale) / textScaleStep).round(),
                    label: '${(appState.textScale * 100).round()}%',
                    onChanged: appState.setTextScale,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text('${(appState.textScale * 100).round()}%', textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const Text('A', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        );
      },
    );
  }
}

void showDisplaySettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SafeArea(
        child: Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 20), child: DisplaySettings()),
      ),
    );

String formatDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Phones have no hover: a tap shows where agreeing / disagreeing experts come from.
void showCountriesSheet(BuildContext context, {required Set<String> agreeIds, required Set<String> disagreeIds, required List<String> riskCountries}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final t = Theme.of(context).textTheme;
      Widget block(IconData icon, String title, Set<String> ids) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$title · ${ids.length}', style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text(describeSplit(appState.expertsByIds(ids), riskCountries), style: t.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where these experts are from', style: t.titleMedium),
              const SizedBox(height: 14),
              block(Icons.thumb_up_alt_outlined, 'Agree', agreeIds),
              block(Icons.thumb_down_alt_outlined, 'Disagree', disagreeIds),
            ],
          ),
        ),
      );
    },
  );
}
