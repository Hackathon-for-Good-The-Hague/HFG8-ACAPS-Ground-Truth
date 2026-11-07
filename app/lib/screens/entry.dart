import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile.dart';

/// Step 1: the group is closed. You only get in with an ACAPS QR code.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _redeem(String code) {
    if (appState.redeemInvite(code) == null) {
      setState(() => _error = 'This is not a valid ACAPS invite. The groups are closed: ask your ACAPS contact for a QR code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _Hero(subtitle: 'A trusted, closed network of humanitarian experts. A few minutes a week to ground-truth ACAPS risk analysis.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.qr_code_2, size: 110, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Scan the QR code you received from ACAPS', textAlign: TextAlign.center, style: t.titleMedium),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _redeem(inviteCodes.keys.first),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR code (demo)'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: _redeem,
                  decoration: InputDecoration(
                    labelText: 'Or type the invite code',
                    hintText: inviteCodes.keys.first,
                    errorText: _error,
                    errorMaxLines: 3,
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _redeem(_code.text)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2: for the MVP you pick a synthetic demo user instead of logging in.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final personas = appState.experts.where((e) => e.persona || !e.simulated).toList();

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(subtitle: 'Invite accepted: ${appState.invitePanel} panel.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Continue as a demo expert'),
                Text('All users are synthetic. No passwords in the demo.', style: t.bodySmall),
                const SizedBox(height: 8),
                for (final e in personas)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Card(
                      child: ListTile(
                        leading: Avatar(nameSeenBy(e, ViewerRole.expert)),
                        title: Text(e.pseudonym, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('Level ${e.level.number}: ${e.level.label} · ${e.homeCountry}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => appState.signInAs(e),
                      ),
                    ),
                  ),
                const SectionLabel('ACAPS moderators'),
                Text('Each moderator has their own account. Reviews are signed with their name.', style: t.bodySmall),
                const SizedBox(height: 8),
                for (final m in moderators)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.tertiary.withAlpha(50),
                          child: Icon(Icons.admin_panel_settings_outlined, color: cs.onSurface),
                        ),
                        title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('ACAPS moderator'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => appState.signInModerator(m.id),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('I am new: create my profile'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  Anonymity _level = Anonymity.pseudonymous;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _pseudo = TextEditingController(text: 'Expert-${DateTime.now().millisecond % 90 + 10}');
  late String _home = appState.invitePanel ?? 'Chad';
  final Set<String> _interests = {};
  bool _notify = true;
  bool _rating = true;
  bool _hideAbroad = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _pseudo.dispose();
    super.dispose();
  }

  bool get _valid =>
      _pseudo.text.trim().isNotEmpty && (!_level.needsRealName || (_first.text.trim().isNotEmpty && _last.text.trim().isNotEmpty));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const SectionLabel('1. How visible do you want to be?'),
          for (final a in Anonymity.values)
            OptionTile(
              title: 'Level ${a.number}: ${a.label}',
              subtitle: a.description,
              icon: anonymityIcon(a),
              selected: _level == a,
              onTap: () => setState(() => _level = a),
            ),
          Text('The public never sees individual answers, whatever level you choose. You can change this later.', style: t.bodySmall),
          if (_level.needsRealName) ...[
            const SectionLabel('2. Your name'),
            Row(
              children: [
                Expanded(child: TextField(controller: _first, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'First name'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _last, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Last name'))),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _level == Anonymity.knownToAcaps ? 'Visible to ACAPS moderators only.' : 'Stored to verify your account. Nobody sees it in the app.',
              style: t.bodySmall,
            ),
          ] else ...[
            const SizedBox(height: 12),
            const InfoBanner(icon: Icons.visibility_off_outlined, text: 'Level 3: we do not ask for your name, and nothing that identifies you is stored.'),
          ],
          SectionLabel('${_level.needsRealName ? 3 : 2}. Pseudonym and countries'),
          TextField(
            controller: _pseudo,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Pseudonym',
              prefixIcon: const Icon(Icons.alternate_email),
              helperText: _level == Anonymity.anonymous ? 'Only you see it.' : 'What colleagues see.',
            ),
          ),
          const SizedBox(height: 12),
          CountryField(label: 'Your country', value: _home, onChanged: (c) => setState(() => _home = c)),
          const SizedBox(height: 12),
          InterestsField(selected: _interests, exclude: _home, onChanged: () => setState(() {})),
          if (_level != Anonymity.anonymous)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _hideAbroad,
              onChanged: (v) => setState(() => _hideAbroad = v ?? false),
              title: const Text('Stay anonymous to colleagues from other countries'),
              subtitle: Text('Colleagues from $_home see your pseudonym; others see "$anonymousName".'),
            ),
          const SectionLabel('Settings'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
            title: const Text('Notify me when ACAPS updates a risk'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _rating,
            onChanged: (v) => setState(() => _rating = v),
            title: const Text('Take part in the rating'),
            subtitle: const Text('You appear under the name your level allows.'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _valid
                ? () {
                    appState.register(
                      level: _level,
                      realName: '${_first.text.trim()} ${_last.text.trim()}',
                      pseudonym: _pseudo.text,
                      homeCountry: _home,
                      interests: {..._interests},
                      notifications: _notify,
                      onRating: _rating,
                      hideFromOtherCountries: _level != Anonymity.anonymous && _hideAbroad,
                    );
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                : null,
            child: const Text('Join the group'),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final String subtitle;
  const _Hero({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 36, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primary, AppColors.ink]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, color: Colors.white, size: 34),
              const Spacer(),
              IconButton(
                tooltip: 'Theme and text size',
                onPressed: () => showDisplaySettings(context),
                icon: const Icon(Icons.text_fields, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Ground Truth', style: t.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(subtitle, style: t.bodyLarge?.copyWith(color: Colors.white.withAlpha(220), height: 1.4)),
        ],
      ),
    );
  }
}
