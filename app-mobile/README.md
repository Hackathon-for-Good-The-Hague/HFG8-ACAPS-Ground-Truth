# Ground Truth: phone version

A copy of `../app` adapted for phones. `../app` stays unchanged as the reference version.

What is different from `../app`:
- Portrait only. The Android app name is "Ground Truth".
- Agree/disagree: a **Who?** button opens a sheet with where those experts are from, since phones have no hover. The moderator gets the same on tap.
- Rating: the scope (my country / my region / all) is a row of chips that scrolls sideways.
- Moderator on a phone: search plus a **Filters** button that opens a sheet with all filters and sorting, with active filters as removable chips. Overview tiles are two per row. Comment filters are chips. Panel filters fold away.
- Light vibration when picking 1-5. The country search is no longer hidden behind the keyboard.

To try it on a real phone without Android Studio: `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080`, then open `http://<this computer's IP>:8080` on a phone on the same Wi-Fi. An installable Android app (APK) needs the Android SDK, which this computer doesn't have.

---


A mobile-first prototype of an expert loop for ACAPS risk analysis.

## Flow

Principle: individual contributions are never shown to the public.

1. **Entry:** the groups are closed, so you need an ACAPS QR code to get in (demo codes `GT-CHAD-7Q4X` and `GT-SDN-3K9M`, or tap *Scan QR code (demo)*). Then you pick a synthetic demo user (no passwords in the MVP), sign in as the **ACAPS moderator**, or create a profile.
2. **Anonymity levels:** 1 = known to ACAPS, 2 = known to colleagues by pseudonym, 3 = fully anonymous. We only ask for a real name at levels 1 and 2. Moving to level 3 deletes it (`real_name: null` in the database, visible under Moderator → Experts). Moving back from level 3 asks for the name again. Every name shown in the app comes from `displayName(expert, viewer)` in `lib/identity.dart`. Experts at level 1 or 2 can also tick "Stay anonymous to colleagues from other countries": colleagues from their own country still see the pseudonym, everyone else sees "Anonymous expert".
3. **Survey (demo risk R1043):** a notification ("ACAPS updated a risk in Chad. Got 2 minutes?"), which you can skip. Then a one-line intro with *More details* and *Start*. Then one screen per trigger (max 3), each with 4 questions: agree with ACAPS (yes/partly/no), likelihood in 6 months (1-5), how bad (1-5), and what ACAPS is missing (optional).
4. **Group summary:** per question: the results, then what colleagues say ACAPS is missing, then the next question. how many have answered (e.g. 6 of 8), distributions marked "you are here" and "ACAPS", and colleagues' comments with agree/disagree. Hovering (or long-pressing) agree/disagree shows where those experts come from. A country is named only if at least 3 of them are from it; the rest are shown as "other countries". You can *Change answer* or tap *Done*.
5. **My forecasts:** open forecasts can be edited. Matured ones show what actually happened, styled like the risk card. Archive risks mature instantly, so the demo doesn't have to wait 6 months, and the demo personas come with simulated history.
6. **Rating (opt-in):** 100 × (1 − Brier) points per matured forecast. Only likelihood is scored. +25 for a comment a moderator marks useful, +50 for a comment used in another risk's analysis. Badges: Super estimator, Useful insight, Cited in analysis, Regular.
7. **Moderator** (side rail on desktop, bottom bar on phones; `?tab=risks` opens a tab directly):
   - *Overview*: comments waiting for review, risks where experts see it differently from ACAPS (likelihood gap and disagreement), countries that need recruiting.
   - *Risks*: search, Active/Archive/All, region, country, sort (to review, disagreement, likelihood gap, response rate, risk level), "only with comments to review", and a slider for minimum disagreement with ACAPS. A risk opens a review page (next to the list on desktop): for each question the results, then the comments right underneath, each with *Useful*, *Use in analysis* (pick the risk) and *Mark reviewed*. Plus a public preview (aggregates only).
   - *Panels*: every country with panel size against the minimum of 3 and the target of 5-10, response rate, region filter and sorting. Each expert opens a sheet with their stats and the raw database record (`real_name: null` at level 3).
   - *Rating*: the same as experts see it.

8. **Opening from a notification:** a tapped notification opens the app with `?risk=R1043` and goes straight to that card. Without a link, a new or updated risk waiting for you opens as a pop-up once per launch (*Not now* skips it).
9. **My answers** (Profile): every answer with the risk status (in progress / happened / did not happen), accuracy, and what happened to your comments (marked useful, used in another analysis, agree/disagree).
10. **Display:** light, dark or high-contrast theme, and text size from 85% to 150% in 5% steps (Profile, or the text icon on the entry and moderator screens).

All experts are synthetic. Their answers are simulated deterministically from the ACAPS rating plus a per-expert "skill". Your profile, answers and comments are saved on the device (`shared_preferences`). **Profile → Reset demo** wipes them.

Not done yet: real QR scanning, passwords, real push notifications, translations, topics, AI support for moderators.

## Run

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.22 or newer).

```bash
cd app
flutter pub get
flutter run -d edge        # or -d chrome, or an Android emulator / device
flutter test
dart run tool/identity_check.dart   # anonymity rules, runs without the Flutter test device
```

On Windows, building for the Windows desktop target needs Developer Mode, because of plugin symlinks. The web target doesn't.

`flutter create .` only generates the missing platform folders. It does not overwrite `lib/`.
