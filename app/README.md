# Ground Truth: Flutter prototype

A mobile-first prototype of an expert loop for ACAPS risk analysis.

## Flow

Principle: individual contributions are never shown to the public.

1. **Entry:** the groups are closed, so you need an ACAPS QR code to get in (demo codes `GT-CHAD-7Q4X` and `GT-SDN-3K9M`, or tap *Scan QR code (demo)*). Then you pick a synthetic demo user (no passwords in the MVP), sign in as the **ACAPS moderator**, or create a profile.
2. **Anonymity levels:** 1 = known to ACAPS, 2 = known to colleagues by pseudonym, 3 = fully anonymous. We only ask for a real name at levels 1 and 2. Moving to level 3 deletes it (`real_name: null` in the database, visible under Moderator → Experts). Moving back from level 3 asks for the name again. Every name shown in the app comes from `displayName(expert, viewer)` in `lib/identity.dart`. Experts at level 1 or 2 can also tick "Stay anonymous to colleagues from other countries": colleagues from their own country still see the pseudonym, everyone else sees "Anonymous expert".
3. **Survey (demo risk R1043):** a notification ("ACAPS updated a risk in Chad. Got 2 minutes?"), which you can skip. Then a one-line intro with *More details* and *Start*. Then one screen per trigger (max 3), each with 4 questions: agree with ACAPS (yes/partly/no), likelihood in 6 months (1-5), how bad (1-5), and what ACAPS is missing (optional). The last screen asks how to credit you if ACAPS publishes the risk: *Real name*, *Pseudonym* or *Anonymous*. The default follows your profile (level 1 → real name, 2 → pseudonym, 3 → anonymous), and real name is unavailable at level 3. Credits only list contributors, never next to answers.
4. **Group summary:** per question: the results, then what colleagues say ACAPS is missing, then the next question. how many have answered (e.g. 6 of 8), distributions marked "you are here" and "ACAPS", and colleagues' comments with agree/disagree. Hovering (or long-pressing) agree/disagree shows where those experts come from. A country is named only if at least 3 of them are from it; the rest are shown as "other countries". You can *Change answer* or tap *Done*.
5. **My forecasts:** open forecasts can be edited. Matured ones show what actually happened, styled like the risk card. Archive risks mature instantly, so the demo doesn't have to wait 6 months, and the demo personas come with simulated history.
6. **Rating (opt-in):** 100 × (1 − Brier) points per matured forecast. Only likelihood is scored. +25 for a comment a moderator marks useful, +50 for a comment used in another risk's analysis. Badges: Super estimator, Useful insight, Cited in analysis, Regular.
7. **Moderator** (side rail on desktop, bottom bar on phones; `?tab=inbox|risks|experts` opens a tab directly). One tab per kind of thing:
   - *Inbox* (badge = open items): only what needs action, and items leave once handled. First, **countries with fewer than 3 experts** (and active risks), where group results could reveal who answered, each with *Invite*. Then **comments to review**, one line per risk. Countries with no experts at all sit in a collapsed backlog at the bottom, each with its number of active risks.
   - *Risks*: search and Active/Archive/All on screen; sort, region, country, "only with comments to review" and minimum disagreement in the filter sheet. **New risk** (button at the bottom right) opens a form: title, type, countries, ACAPS probability/impact/level, rationale, up to 3 triggers. It shows how many experts will be asked and publishes the risk to them as Active; such risks start with no answers and can be edited or deleted later. A risk opens a review page (next to the list on desktop), which opens on the new comments: for each question the results, then the comments right underneath, each with *Useful*, *Use in analysis* (pick the risk) and *Mark reviewed*. A warning with *Invite* shows when a risk's country has too few experts. *Publish* shows what may be published (aggregates, plus with *Credit experts who agreed* the contributors who chose a real name or pseudonym for this risk and the number of anonymous ones) and exports it as JSON, for this risk or for all risks with at least 3 respondents (schema `acaps-ground-truth/public-view/v1`: ACAPS rating, respondent count, and per question agreement counts plus likelihood and severity distributions; no comments, no respondent countries, no names next to answers; with credits on, a `contributors` list and `anonymous_contributors` count).
   - *Experts*: everyone, filtered by country and sorted by points, accuracy, answers or name. *Invite experts* (and the QR icon in the moderator's top bar, on every tab) gives the invite QR code for any country (download as PNG, copy link, copy code). The QR code opens the app with `?invite=<code>`. Each expert opens a sheet with their stats and the raw database record (`real_name: null` at level 3). *Leaderboard* shows the rating as experts see it.

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
