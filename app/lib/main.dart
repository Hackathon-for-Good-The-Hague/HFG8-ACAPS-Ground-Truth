import 'package:flutter/material.dart';

import 'screens/entry.dart';
import 'screens/home.dart';
import 'screens/moderator.dart';
import 'store.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A tapped push notification opens the app with ?risk=<id> (web) or the
  // same value from the notification payload (mobile).
  appState.deepLinkRisk = Uri.base.queryParameters['risk'];
  // A scanned invite QR code opens the app with ?invite=<code>.
  final invite = Uri.base.queryParameters['invite'];
  appState.load().then((_) {
    if (invite != null && !appState.signedIn) appState.redeemInvite(invite);
  });
  runApp(const GroundTruthApp());
}

class GroundTruthApp extends StatelessWidget {
  const GroundTruthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final contrast = appState.theme == AppTheme.contrast;
        return MaterialApp(
          title: 'Ground Truth',
          debugShowCheckedModeBanner: false,
          theme: contrast ? buildContrastTheme() : buildTheme(Brightness.light),
          darkTheme: contrast ? buildContrastTheme() : buildTheme(Brightness.dark),
          themeMode: switch (appState.theme) {
            AppTheme.light => ThemeMode.light,
            AppTheme.dark => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * appState.textScale)),
              child: child!,
            );
          },
          home: _root(),
        );
      },
    );
  }

  Widget _root() {
    if (!appState.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (appState.error != null) {
      return Scaffold(body: Center(child: Text('Could not load data:\n${appState.error}')));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: appState.sessionModerator
          ? ModeratorShell(key: ValueKey('moderator-${appState.sessionModeratorId}'))
          : appState.me != null
              ? HomeShell(key: ValueKey('home-${appState.me!.id}'))
              : appState.invitePanel == null
                  ? const InviteScreen(key: ValueKey('invite'))
                  : const SignInScreen(key: ValueKey('signin')),
    );
  }
}
