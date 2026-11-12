# Ironyx — TODO (two-day finish)

Replanned 2026-09-20. The full 12-week plan, the post-launch roadmap and both
engineering audits are unchanged in [`docs/archive/TODO-full-plan.md`](docs/archive/TODO-full-plan.md).
Older references in code and docs ("TODO.md A2.14", "Roadmap Phase 5", "C6",
"D1", "Week 2") point into that file.

Owner tags: **me** = you, the account holder (consoles, passwords, devices);
**dev** = code or file changes Claude can do in this repo.

## Where the app really stands

**Update 2026-11-03 (after the drive failure).** This section below is from
2026-09-20; these are the current facts:

- The original drive failed. Work from Oct 5 to 22 that had never been pushed was rebuilt from
  recovered files as commit `a27f910` on `recovery/2026-10-22`. The audit
  record is `RECOVERY_MERGE_MANIFEST.json`.
- **1.0.3 (versionCode 4) is on a Play track.** The owner's SM N970F installed
  it from Play on 2026-10-24. Its signer `5D:8A:EA:72…` is Google's
  app-signing key, which explains the C6 "different signer" note: Play
  re-signs uploads. A locally signed APK therefore cannot update that
  install; test release builds through a Play testing track. The next upload
  needs versionCode ≥ 5.
- **The reconstruction was verified against that Play build.** Rebuilt from the
  same `F:\Ironyx` path, the Dart machine code is byte-identical, the strings,
  614 bundled assets and the app's own Android resources match, and Library and Timer
  screens are pixel-identical side by side. The Dart data snapshot differs
  by a few bytes in what looks like ordering. That is not fully explained, and the visual check
  found no visible difference.
- Upload keystore and `key.properties`: backed up to the owner's Google Drive
  (owner-reported 2026-11-03).
- `flutter test`: **1,161 passed, 2 skipped, 0 failed** (2026-11-12; was
  1,041 on 2026-11-10 and 876 on 2026-11-05).
- Fixed 2026-11-05: a debug build sometimes showed a full-screen
  `'_dependents.isEmpty': is not true` after pressing Save in a set's "RPE
  and rest time" dialog. The dialog disposed its text controllers while it
  was still animating closed. The body-measurement dialog on Progress had
  the same fault. Each dialog now owns its controllers. Release builds strip
  the assertion, so the Play build never showed the screen. **Not checked on
  a phone.**
- Fixed 2026-11-05, same dialog: an RPE or rest time could not be removed
  once entered, and an out-of-range value made Save do nothing without
  saying why.
- Changed 2026-11-05: the debug error screen now names the first error of a
  burst, the widget blamed and the top stack frames, and the release one is
  translated (`UncaughtErrorView`, `ErrorBurst` in `core/error_reporting.dart`).
- Fixed 2026-11-05: the body-measurement dialog closed and saved nothing,
  without a message, when the weight was empty, zero or not a number, and
  it accepted any positive weight and any body-fat value. It now stays open
  and says what it accepts: 25 to 350 kg (the limits Personal details
  already used, now shared in `core/body_limits.dart`) and 2 to 70 % body
  fat. Rows already stored outside those limits are left alone.
- Fixed 2026-11-05: a measurement's day is stored as UTC midnight and was
  read back as local time, which west of UTC is the evening before.
  Reproduced with `TZ=PST8PDT flutter test`: the entry showed the previous
  day, saving an edit overwrote the previous day's entry, deleting removed
  it, and five edits moved the date back five days. `BodyMetrics.fromDrift`
  now carries the stored day as a local date. East of UTC, which includes
  the owner's phone, none of this was visible. Rows already damaged by an
  edit west of UTC cannot be told apart from correct ones and are not
  repaired.
- Fixed 2026-11-05: Personal details logged the weight under the UTC date,
  so a weight saved between midnight and 03:00 in Baghdad went to
  yesterday. It uses the local day now.
- CI runs the calendar-day and week test files in three more time zones
  (2026-11-05; the step passes). Locally, on Windows, the equivalent is
  `TZ=PST8PDT flutter test` (three-letter zone names only). That gives a
  fixed offset: Windows cannot simulate a zone that changes its clocks, so
  the clock-change tests are only meaningful on CI.
- Added 2026-11-05: **Settings → Week starts on** (Saturday, Sunday or
  Monday; Monday until chosen, so nothing regroups on update). It feeds the
  weekly totals and streaks, the dashboard week card and day strip, the
  history calendar and the Progress weekday chart, through one value
  (`WeekStart`, `weekStartControllerProvider`). Stored on the device like
  the weight unit: not in exports or cloud backups, so a restore on a new
  phone starts at Monday. Nothing is stored by week, so switching only
  regroups what is shown.
- Changed 2026-11-05, with it: weekly totals, streaks and the Progress
  weekday chart were grouped by UTC weeks and days while the dashboard used
  the phone's time. At UTC+3 a workout between midnight and 03:00 on a
  week's first day was counted in the week before. They all use the
  phone's time now, so some past workouts near a week boundary moved to the
  neighbouring week on the charts. The offset is one constant per query: a
  workout within an hour of midnight on a week's first day, in a season
  with the other clock setting, can still land a day off.
- Fixed 2026-11-05: "last week" and the weekly streak stepped
  back 168 hours, which lands on 23:00 the day before across a clock
  change, so the streak broke for that week. They step by calendar week
  now. Iraq has no clock changes, so the owner's phone never showed it.
  The tests for it pass on CI under America/Los_Angeles and
  Pacific/Auckland, which change their clocks. The old code was reasoned to
  fail there, not run there.
- Fixed 2026-11-05: number fields dropped a decimal comma as it was typed,
  so "82,5" in a set row was logged as 825 kg, and dropped Arabic-Indic
  digits entirely. Every number field (set rows, RPE and rest, body
  measurement, Personal details, timer, a program's target sets) now goes
  through `NumberInputFormatter` in `core/formatters/number_input.dart`,
  which reads `,`, `٫` and `،` as a decimal point and Arabic-Indic and
  Persian digits as 0–9. A comma is never a thousands separator. **Not
  checked:** what the owner's Samsung keyboard actually sends in Arabic.
  Not changed: the XLSX importer still reads text cells with
  `double.tryParse`, so a cell holding the text "82,5" is skipped.
  **Checked on the SM N970F, 2026-11-05:** in English (en-GB) Samsung's
  number keyboard shows a comma key that sends nothing in these fields
  (Android's decimal input type accepts only "."); the dot key works.
- Changed 2026-11-05, seed 17 → 18 (304 exercises): the Intermediate 3-,
  4- and 5-day programme workbooks name 40 exercises. 37 were already in
  the catalogue under other names and are now aliases of them; 3 were
  missing from free-exercise-db and were written for the app (Behind-the-
  Body Cable Curl, Lean-In Lateral Raise, Banded Hip Abduction: no images,
  source `ironyx` in ASSETS-LICENSE.md). Both importers now match names and
  aliases (`ExerciseDao.exerciseIdsByLookupName`); the workout importer's
  private name list is gone, and three of its matches were wrong (low-
  incline press to the flat press, chest-supported machine row to the
  cable row, leg-press calf raise to the standing calf raise). Before this,
  importing those workbooks created 19 bare custom duplicates. Upgrade from
  seed 17 checked on the phone (debug build): 304 exercises, data kept.
- Closed 2026-11-05: the owner confirmed those workbooks were never
  imported into the Play app (they were a reference for which exercises to
  add), so no custom duplicates exist to merge.
- Done 2026-11-05, seed 23: pictures for the three exercises written for
  the app, from images the owner generated (two with ChatGPT, the lateral
  raise with Google Gemini). Originals, checksums and what is unverified
  about the tools' terms are in ASSETS-LICENSE.md;
  `scripts/prepare_owner_images.py` makes the bundled frames. The Lean-In
  Lateral Raise's steps now lean away from the post, as its picture does
  (owner's decision). The exercise sheet shows every picture of an exercise
  (start and end), swiped between. **Open:** the owner has to read the
  ChatGPT and Gemini terms before a release ships the images.
- Changed 2026-11-12, Settings (reviewed, the review re-checked at the
  owner's request, then fixed one item at a time, on
  `settings/review-2026-11-12`). **Not in the 1.0.5+6 bundle.**
  - **Fixed: "Delete all data" left the user's data on the phone.** It
    cleared the database only. Every import, and every cloud restore,
    first saves a full snapshot of the data (name and email included) into
    the app's private storage and keeps the last three; nothing ever
    removed them, so after "Delete everything" Restore snapshot brought the
    data back, and the confirmation's "This cannot be undone" was untrue.
    An open workout (kept outside the database) and the user's own
    exercises (typed in, or made by an XLSX import) survived as well. Now
    `DataExportService.deleteAllUserData` also deletes custom exercises
    and, after the database delete succeeds, the snapshots
    (`deleteSnapshots`); and one `eraseLocalData` (settings/domain) does
    the database, the snapshots, the open workout and the built-in
    programs for both Settings and the account-conflict "erase and
    continue", which had their own copies. The first review had proposed a
    snapshot *before* deleting, which would have kept another full copy;
    instead the dialog offers "Export first", a copy the user chooses and
    places. The delete runs behind a progress dialog and a failure says so
    (it escaped the tap handler). Three strings, en/ar, and the
    confirmation's text now lists what goes. Android's own backup is off
    (`allowBackup="false"`), so the snapshots never left the phone.
    **Found while testing:** the progress dialog's helper started its work
    before the dialog was built, so a fast failure left the spinner up for
    good; it waits for the dialog now. **Tested:** custom exercises go,
    even once used, the catalogue stays; snapshots go and nothing else in
    their folder; a failed delete keeps them; end to end, the custom
    exercise, the snapshot and the open workout are gone; "Export first"
    deletes nothing; a failure shows its message and closes the spinner.
    The custom-exercise and end-to-end tests fail on the old code. The
    account-conflict erase test now also checks the old account's snapshot
    is gone. **Not checked:** on the phone. **Open:** the account-conflict
    erase has no error handling of its own (as before this change).
  - **Fixed: restoring a snapshot could lose the current data for good.**
    An import and a cloud restore save a snapshot of what they replace;
    Restore snapshot did not, so picking the wrong one was final. It does
    now (`restoreSnapshot` with `createSnapshot: true`). The new snapshot
    is the newest and is kept; past three, the oldest goes, which may be
    the one just restored, whose data is the live data by then.
    **Tested:** restoring an empty snapshot over a history, then the
    snapshot saved by that restore, brings the history back (on the old
    code there was no second snapshot).
  - **Fixed: import errors were English only, or lost.** The importer's 22
    refusals each had an English message, shown as it was in Arabic too;
    and those raised while applying (a backup missing data, an exercise
    name already here) were caught as the generic "Import failed", their
    reason lost. `ImportValidationException` now carries an
    `ImportProblem`, seven kinds (not an export, made by a newer app, too
    old, incomplete, exercise clash with its name, damaged, app mismatch),
    and the Data section says each in the user's language
    (`ImportValidationL10n.messageFor`, seven strings, en/ar), for a file
    picked, a refusal while applying, and a snapshot restore. The English
    detail stays in `message`, for logs and tests. Cloud restore already
    translated its own (as "corrupt") and is unchanged. Grouped, at the
    owner's choice, rather than 22 translations of row-level detail a user
    cannot act on. **Tested:** each kind on the existing test that
    triggers it (not JSON, newer format and schema, too-old schema,
    incomplete replace, exercise clash and its name, a damaged row); every
    kind has its own sentence, and an Arabic one.
  - **Fixed: Export showed nothing while it ran, and failed silently.** It
    reads every table with nothing on screen, the tile still tappable (a
    second tap started a second export), and a failure to build or to save
    escaped the tap handler. The backup is now built behind the progress
    dialog; the system's save screen then opens (no dialog can stay over
    it); a failure at either step says "Couldn't export your data" (new
    string, en/ar) and is logged. The 20 MB figure in `buildJsonExport` is
    a logged warning, not a refusal, so a large export still saves.
    **Tested:** the spinner shows while the export is built, and a failed
    build closes it and says so (fails on the old code: no spinner). The
    save step is not reachable in a test (the file picker has no test
    channel). **Not checked:** on the phone.
- Changed 2026-11-12, CI: **Flutter pinned to 3.47.9.** CI used whatever
  stable was current, and Flutter 3.50.0 (released 2026-11-11/12) deprecates
  `package:flutter/material.dart`, moved into the separate `material_ui`
  package; with `--fatal-infos` that failed `flutter analyze` on 134
  imports, so every pull request failed (first seen on #6). 3.47.9 is the
  last version CI passed on (#4, #5). This machine has 3.47.5. **Open:**
  moving to Flutter 3.50, which needs the `material_ui` package added (a new
  dependency, the owner's decision) and every Material import changed; and
  whether to pin the local Flutter to the same version as CI.
- Changed 2026-11-11, Library and Timer tabs (reviewed together, then
  fixed one item at a time, on `library-timer/review-2026-11-11` from
  `main` after #4 and #5 merged). **Not in the 1.0.5+6 bundle.**
  - **Fixed: searching in Arabic found nothing.** The search is SQL over the
    stored English names and aliases; the Arabic names are a Dart table
    (`exercise_catalogue_ar.dart`) the database does not hold, and the seed
    has no Arabic aliases. A query with an Arabic letter
    (`containsArabic`) is now matched in memory against the name shown and
    the stored name (`matchingDisplayedName`), over the list the filters
    give; a Latin query stays in SQL, aliases included. Same in the
    exercise picker sheet. The Progress lift picker's fold moved to
    `core/formatters/search_fold.dart` (`foldForSearch`, `matchesSearch`,
    renamed from `liftMatchesQuery`) so both use one. **Tested:** an Arabic
    query typed without marks finds "ضغط بار على مقعد مستوٍ" (fails on the
    old code); an unknown word finds nothing; `containsArabic`.
    **Not checked:** on the phone.
  - **Fixed: a search dropped the filters.** The page watched either the
    search or the filters, so with text in the box the muscle, equipment
    and movement filters were ignored while their chips still showed as
    active. `ExerciseDao.filterBy` now takes the search too (`query`, name
    or alias), each criterion narrowing the others; `searchByName` calls
    it, and the separate search provider, left with no user, is removed.
    Same for the picker sheet's muscle filter. **Tested:** the query with a
    search and a filter, a blank search, no match; on the page, "pu" with
    Chest gives Push-Up and not Pull-Up (fails on the old code).
  - **Fixed: the custom timer had no upper limits.** Any number was taken:
    80000 rounds built 160,000 phases, which the engine walks five times a
    second and the controller tried to schedule a notification for, one
    each. Now at most 99 rounds (`kMaxTimerRounds`) and 3,600 s per phase
    (`kMaxTimerPhaseSeconds`), checked by `checkCustomTimer` in the domain;
    the builder shows which limit was passed (two new strings, en/ar; since
    replaced by errors under the field, below) and starts or saves nothing, and `TimerPresets.custom` throws past them, so
    no caller can build one. **Not covered:** presets read back from the
    database (`decodeTimerPhases`) are not re-checked, so a restored backup
    could still hold one made before this. **Tested:** the limits
    themselves pass, one past fails, the factory throws, and on the page
    80000 rounds shows "Rounds can be at most 99." (fails on the old code).
  - **Fixed: in Arabic the Library was in no visible order.** The queries
    sort by the stored English name. The list and the picker sheet are now
    sorted by the name shown, folded as a search is (so أ and ا sort
    together), ties by the stored name (`sortedByDisplayedName`); in
    English nothing moves. **Tested:** العقلة, تمرين الضغط, سكوات خلفي in
    that order (by the English names سكوات خلفي came first; fails on the
    old code).
  - **Fixed: equipment icons and Arabic equipment names in the Library.**
    `ExerciseSummary` carried only the equipment's names, and both the
    icon and the Arabic name are keyed by id. A comment claimed the seed
    keeps each name equal to its id; it does not ("Barbell", "barbell").
    So every row and card had the generic "more" icon, and in Arabic every
    row, card and picker line showed English equipment (the review had
    said the rows were translated: wrong, only the detail sheet was, by
    id). The summary now carries `equipmentIds` too, the icon and the
    names (`localizedEquipmentNames`) are looked up by id, and the
    equipment filter's menu is translated (`Equipment.localizedName`).
    **Tested:** a bodyweight row has its icon and no row has the generic
    one; in Arabic a row's detail line reads "· بار ·" and the filter lists
    "وزن الجسم" (both fail on the old code).
  - **Fixed: searches piled up, and Retry reloaded the wrong thing.**
    `exercisesFilteredStream` was kept alive per argument set, so every
    search typed and every filter combination tried stayed a live query,
    re-run on every exercise change, for as long as the app ran; it is
    released now once nothing shows it. Retry on a failed search or filter
    reloaded the full list instead, so it could not recover; it reloads the
    query on screen. The picker sheet's error had no Retry; it has one.
    **Tested:** a released search no longer exists; after a failed search,
    Retry runs that search again (on the old code the count stayed at 11,
    the first try plus Riverpod's ten retries). Both fail on the old code.
  - **Changed: saved timer presets have names, and can be deleted.** Every
    saved preset was named "Custom", so a list of them told them apart only
    by their numbers; and nothing could delete one (the DAO had `remove`,
    no screen called it). "Save preset" now asks for a name, filled in with
    the formula ("30s work / 10s rest × 8"), up to 40 characters, a blank
    one saving the formula. Each saved preset has a menu with Delete, and
    a snack bar offers Undo, which puts the row back with its own creation
    time, so in its place (`TimerPresetDao.take` / `restore`). The delete
    message replaces a "Preset saved." still showing, or its Undo would
    queue behind it. Four new strings, en/ar. Presets saved before keep
    the name "Custom". **Tested:** take and restore keep the order; a
    preset saved under a name, deleted and brought back; a blank name
    saves the formula. The naming test fails on the old code.
    **Not checked:** on the phone.
  - **Fixed: starting a timer could lose a session, start two, or fail
    silently.** `startTimer` now (1) opens a session already running
    instead of replacing it: tapping any preset while one ran in the
    background threw the running one away unsaved (found while planning
    this item; the review had not listed it); (2) ignores a second tap
    while the first is still starting, since the wait on the notification
    permission let a double tap start two sessions and push two timer
    screens; (3) shows "Couldn't start the timer." and logs a failure,
    which escaped the tap handler. Saving a preset shows "Couldn't save the
    preset." on failure. Two new strings, en/ar. **Tested:** all four, each
    failing on the old code.
  - **Fixed: a timer session's duration included its pauses.** It was
    saved as the span from start to end, so a 4-minute timer paused for
    ten minutes was 14 minutes, on Home's "Last timer" row too. It is now
    the engine's elapsed time, which pauses do not add to, at most the
    planned length; start and end are unchanged. Sessions already saved
    keep their figure (owner's choice). To test it the controller now
    takes its time from `clockProvider`, as the rest of the app does, and
    hands that clock to the engine. **Tested:** 5 s, a ten-minute pause,
    7 s saves 12 s (with the old formula, 612); a session run out saves
    its planned 5 s.
  - **Fixed: two small Library faults.** An active filter chip showed an
    "×", but it sat inside the chip's menu button, so tapping it opened
    the menu again; the "×" is now its own button ("Clear Muscle filter",
    new string, en/ar) and clears that filter, while the rest of the chip
    still opens the menu. And `%` and `_` typed in the search were LIKE
    wildcards, so a search for "_" matched every exercise; they, and the
    escape character, are escaped now. **Tested:** the × clears the filter
    with no menu opened; "_", "%" and "0% e" find only the exercise holding
    them. Both fail on the old code.
  - **Performance: bundled pictures are decoded at the size shown.** The
    608 pictures are 600×400, about 1 MB each decoded, and a phone row
    shows one in a 56 dp square; scrolling the catalogue filled Flutter's
    100 MB image cache over and over. `ExerciseThumbnail.decodeWidth` now
    decodes a bundled picture at its shown width in device pixels: rows at
    1.5 times the square (so a 3:2 picture is still as tall as it, and a
    2:3 one as wide, when cropped to fill), cards at their own width.
    About 0.13 MB a row on this phone instead of 1 MB. Remote video
    thumbnails keep their own size: a missing one is told by its exact
    120×90. Nothing looks different. **Tested:** with a decode width the
    picture is a `ResizeImage` at that width times the pixel ratio, shape
    kept; without one, the full asset. Not run on the old code: the test
    uses the new parameter. **Not checked:** sharpness on the phone.
  - **Refactor: one exercise search for the Library and the picker.** Both
    screens had their own copy of the search box state, the typing delay,
    the choice of query, the Arabic match and the sort, and the row, the
    card and the picker each built the "muscle · equipment · pattern" line;
    every fix above had to be made twice. They now share
    `library/presentation/exercise_search.dart`: `DebouncedSearch` (a
    mixin), `exerciseSource` (which query, also what Retry reloads),
    `shownExercises` (Arabic match, then order) and `exerciseDetailLine`.
    No behaviour change: every existing Library, picker and editor test
    passes unchanged; four new tests cover the shared functions.
  - **Changed: the custom timer builder.** It now shows how long the timer
    runs as it is typed ("Total 05:20 · 16 intervals"), where that was
    known only once it had started. A value out of range is marked under
    its own field ("At least 1", "At most 99") instead of in a snack bar
    that did not say which field it meant; errors show once Start or Save
    has been pressed, then follow the typing, so a half-typed value is not
    marked. Rest may be 0, a work-only timer, which the engine always ran
    and the builder refused; its formula reads "30s work × 8", not "… /
    0s rest × 8". Four new strings, en/ar; the three the snack bar used are
    removed (`timerPositiveValuesRequired`, `timerRoundsTooMany`,
    `timerPhaseTooLong`). **Tested:** the total follows the rounds; a field
    is marked only after Start and clears as it is fixed; zero rest gives a
    work-only timer and its formula. All three fail on the old code.
  - **Fixed: the completion sound and haptic could play more than once.**
    `TimerController._finish` cleared the engine first but played the cues
    unconditionally, so a second call (the last interval running out as
    End is pressed) or a `stop()` on an idle timer played them again; only
    the session write was guarded. It now returns when there is nothing to
    finish. **Tested:** three ends play the cues once and save one session
    (on the old code the haptic played three times).
    This was the last of the fourteen Library and Timer review items.
  - **Checked on the phone, 2026-11-12** (debug build of `6e1454d`, the
    owner's data, Arabic): the Library lists its 304 exercises in Arabic
    order (أرجحة…, أسطوانة…, البلانك…), equipment in Arabic in every row
    ("كيتل بل", "بار", "وزن الجسم"), the bodyweight icon on bodyweight rows,
    and the pictures sharp at the reduced decode size; the timer builder
    shows "المجموع 05:20 · 16 فترةً", and "Save preset" opens the name
    dialog filled with the Arabic formula and a 24/40 counter (cancelled,
    nothing saved). **Not checked on the phone:** an Arabic search (adb
    cannot type Arabic), filter chips, deleting a preset, starting a timer
    (it would run on the owner's phone), and TalkBack.
- Changed 2026-11-11, Workouts tab (reviewed like Home and Progress, then
  fixed one item at a time, on `workouts/review-2026-11-11`, branched from
  `home/review-2026-11-11`). **Not in the 1.0.5+6 bundle.**
  - **Performance: typing in an open workout no longer rebuilds the tab.**
    The page watched the whole draft to show the start button or the resume
    banner, and the draft changes on every weight and rep typed: each
    keystroke rebuilt the page, regrouping the entire history by month and
    the calendar's set of days with it. A small `_StartOrResume` widget now
    reads only the draft's exercise count; the page does not depend on the
    draft at all. **Tested:** with Flutter's rebuild hook, typing a weight
    and reps rebuilds neither the page nor the history list (on the old
    code the page rebuilt), and an added exercise still reaches the banner.
  - **Fixed: program failures were invisible.** If the programs failed to
    load, the row showed nothing, and the heading its "what is a program"
    line as if there were none; it now shows "Failed to load programs"
    (new string, en/ar) with Retry, and the line appears only once the
    list is known to be empty. A card waited for its program before
    opening, and a failure there escaped the tap handler unhandled, so the
    card did nothing; the wait is now capped at 600 ms and any failure is
    logged, and the page opens anyway on its own loading or error state,
    which has Retry. A double tap opened the program twice; it opens once.
    **Tested:** all three, each failing on the old code. **Found:** the
    error appears only after Riverpod's retries (see the next line).
  - **Fixed: the XLSX import.**
    - **A re-import could break every later import.** Imported workouts
      sit at 12:00 UTC on their date, and the duplicate check read "the"
      workout there with `getSingleOrNull`, which throws on two. Two get
      there when an edited file is re-imported (its changed session is
      not a duplicate, so it is added beside the old one) or when two
      sessions share a date. From then on every import of the file failed
      as "could not read". Each workout at that time is compared now.
      **Tested:** reproduced on the old code ("Bad state: Too many
      elements"); now the identical one is found and a new one is not.
    - **Size limit:** files over 10 MB (`kMaxWorkoutXlsxBytes`) are refused
      before they are read, with a message (new string, en/ar); `parse`
      checks again.
    - **Off the UI thread:** unzipping and walking the sheets runs through
      `compute`; it froze the app while a workbook was read. Matching names
      against the database stays on the main isolate. The rules are
      unchanged and every existing import test passes through the new path.
    - **Known risk, not fixed (owner's choice):** an XLSX is a zip, so a
      small file can unpack to far more than 10 MB. Checking the unpacked
      size needs the `archive` package as a direct dependency (it is
      already a transitive one, through `excel`). Only the person who picks
      the file is affected, and nothing is written before they confirm.
    - **Unchanged, noted:** re-importing an edited file adds the changed
      session beside the old one rather than replacing it.
  - **Fixed: the calendar reached one workout per day.** Tapping a day
    opened the first workout found, the latest, so a morning session on a
    two-session day was reachable only from the list. A day with one
    workout still opens it; with several, a sheet lists them ("Workouts on
    {date}", new string, en/ar), as the same rows as the history list, and
    opens the one chosen. The owner had first picked "scroll the list to
    the day"; the sheet was chosen instead because the rows are built
    lazily and vary in height, so a jump far down the list cannot land
    reliably. **Tested:** one workout opens directly (unchanged); several
    ask, and the earlier one opens (fails on the old code). Pinned clock,
    so the tests run at any hour.
  - **Changed: an open workout is resumed from a filled button.** It was a
    plain card ("Workout in progress" over "3 exercises logged · tap to
    resume"), lighter than the "Start workout" button it took the place
    of, though an open workout is the most pressing thing on the tab. It
    is now the same filled button, with play, reading "Resume workout" or
    "Resume workout · 3 exercises" (new string `trackerResumeWithCount`,
    en/ar). The three strings only the card used are removed
    (`trackerResumeSemantic`, `trackerTapToResume`,
    `trackerResumeWithExercises`). **Tested:** the button, its icon and
    that it opens the workout (fails on the old code); the count updates as
    exercises are added. **Not checked:** on the phone.
  - **Changed: program order.** The query orders by the stored name, byte
    by byte, so the user's own programs fell between the built-in ones and
    "Zeta" came before "alpha". The row now shows the user's programs
    first, then the built-in ones, each by the name shown, ignoring case;
    sorted in the widget because the shown name can be a translation. The
    review had said the order looked shuffled in Arabic: wrong, the three
    built-in Arabic names happen to sort as the English ones do (as the
    phone showed). **Tested:** alpha, Zeta, Full Body, Push / Pull / Legs
    in that order (fails on the old code).
  - **Changed: a workout with no load shows its sets, not "0 kg".** A
    bodyweight or timed-only session read "0 kg", as if nothing was done.
    Its row now shows its completed sets ("12 sets", new plural
    `trackerSetCount`, en/ar), and a screen reader hears "Workout on
    {date}, 12 sets" (`trackerWorkoutSemanticSets`). Rows with load keep
    their kilograms, and month totals are unchanged. The counts come from
    one `GROUP BY` for the whole history
    (`WorkoutDao.watchCompletedSetCountByWorkout`, provider
    `workoutSetCounts`), not a query per row; while they load, a row keeps
    its volume. **Tested:** the query (completed sets only; workouts with
    none absent) and the row (fails on the old code). **Not checked:** on
    the phone.
  - **Refactor: `tracker_page.dart` split.** 1,175 lines and 15 widgets
    became the page (scaffold, headings, calendar toggle, menus, start and
    resume; 484 lines) and three files in `tracker/presentation/widgets/`:
    `program_strip.dart`, `history_list.dart` (the list, month headings and
    the day sheet) and `history_row.dart` (a row, its title fitting and its
    date tile). The month grouping left the list's widget for a pure
    `groupHistoryByMonth` in `tracker/domain/history_grouping.dart`, with
    four unit tests (empty, months and their totals, a month in two years,
    a month's first and last minutes). Moved, not rewritten: sorted line by
    line, old and new differ only in `super.key` on the now-public
    constructors, doc comments, the grouping's signature and one line the
    formatter rewrapped. Every existing test passes unchanged.
  - **Changed: one import menu.** The Programs and History headings each
    had a "⋮" holding one rare item (CSV and XLSX import). Both are now in
    a single "⋮" in the app bar ("Import": "Import programs from CSV",
    "Import workouts from XLSX"; two new strings, en/ar), and the headings
    keep only their everyday action ("New", the calendar). The no-programs
    card keeps its own import button. The two old menu tooltips are
    removed (`trackerProgramOptions`, `trackerHistoryOptions`). **Tested:**
    one menu with both items and no section menus (fails on the old code);
    the existing import tests now open it.
  - **Fixed: the XLSX confirm dialog's dates and spacing.** It showed the
    range as ISO strings ("2026-11-04") in either language; the dates are
    formatted like every other date in the app ("4 Nov 2026", "4 نوفمبر
    2026"), keeping the workbook's calendar day (UTC midnight, formatted by
    its own fields, so no time zone moves it). The gaps use the spacing
    scale instead of literal 16 and 8. The body is its own widget,
    `WorkoutXlsxImportPreview`, so it is tested without the file picker.
    **Tested:** English and Arabic dates, and "No dates" for an empty file.
    Not run on the old code: the body was not a widget of its own then.
  - **Fixed: a history row was read twice by a screen reader.** Checked
    first, by dumping the row's semantics node: its label was followed by
    every text inside it ("Incline Press, Chest-Supported Row. Workout on
    11 Nov 2026, 1,200 kg volume", then "Incline Press, +1, 1:46 PM · 45m,
    1,200 kg"), and the time and duration were only in that second half.
    The row is now read once: the exercises, the date and volume (or
    sets), then the time and duration (`excludeSemantics`, with the tap
    action on the label, since excluding the children drops the
    InkWell's). The day sheet's rows are the same widget. **Tested:** the
    label holds everything once, without the "+1" pill, and the semantics
    tap opens the workout (fails on the old code). **Not checked:** with
    TalkBack on the phone.
  - **Changed: history loads as placeholder rows.** A spinner sat in the
    middle of the page while the rest of the app loads as shimmer shaped
    like its content. Three `WorkoutHistoryRowPlaceholder`s (date tile,
    two lines, volume) stand in now, spoken as "Loading history" (new
    string, en/ar). **Tested:** no spinner, three placeholders, the spoken
    label. Not run on the old code: the test names the new widget.
    This was the last of the twelve Workouts review items.
  - **Checked on the phone, 2026-11-11** (debug build of `1491a49`, the
    owner's data, Arabic): one "⋮" in the app bar holding both imports, in
    Arabic; the Programs heading has only "New" and History only the
    calendar; a history row is announced once, from the accessibility
    dump: all eight exercises, the date, volume and record, then "9:29 ص،
    58 د". The program order is Full Body, Upper / Lower, then Push / Pull
    / Legs: the database copy showed the first two with `is_built_in = 0`,
    which is by design (editing a built-in program makes it the user's, so
    a re-seed cannot overwrite it), so they sort as the user's. **Found,
    not changed:** `ProgramL10n.displayName` picks the Arabic name by id
    alone, so an edited and *renamed* built-in program would still show
    the built-in's Arabic name, against what `program_catalogue_ar.dart`
    documents; nothing visible with this data (the names were kept).
    **Not seen on the phone:** the day sheet, "N sets", the 10 MB message
    and the history shimmer, which this data or speed does not produce.
- Changed 2026-11-11, Home tab (reviewed like Progress, then fixed one
  item at a time, on `home/review-2026-11-11` from `main`). **Not in the
  1.0.5+6 bundle**, which was built from `a6c3305`: the next upload needs
  versionCode 7.
  - **Fixed: the streak tile could not read more than "8 wk".** It was
    counted from the week card's eight-week window, so twenty straight
    weeks showed 8. It now has its own provider,
    `dashboardStreakWeeks`, over the whole history (one row per week since
    the first workout), so a failure there costs the tile and not the week
    card. The rule itself is one function, `currentStreakWeeks` in
    `consistency_calculators.dart`, which Progress's consistency card now
    calls too: a week counts with any finished workout, and an empty week
    so far does not break the streak. Progress matched weeks by exact
    instant, Home by calendar day; the shared rule matches by calendar day,
    which is what survives a clock change. `WeekSnapshot.streakWeeks` is
    gone, so nothing can read the capped figure again.
  - **Tested:** the shared rule (empty, order, an empty week so far, a zero
    or missing week, 60 weeks, Saturday buckets, clock-change weeks) and
    the provider (20 weeks reads 20; a week off ends it; none is 0; it
    regroups when the first day of the week changes). The old figure was
    reproduced first: 20 straight weeks read 8. **Not checked:** on the
    phone.
  - **Fixed, at the owner's request: Progress's streaks were capped by the
    range.** Both were counted inside the selected range, so on "1M"
    neither could pass about five weeks, and the longest left out any run
    begun before the range. Its explainer already said "Longest streak is
    your record across your whole history". Both now count over every week
    since the first workout (`allTimeWorkoutFrequency`, one provider and
    one query that Home's tile reads too; `calculateConsistency` takes it
    as `history`, and a new shared `longestStreakWeeks`). Adherence is
    still a figure about the range. With it: `consistencySummary` now
    passes the app's clock, so "this week" no longer comes from the device
    clock while the range comes from `localNow`. The explainer said a
    streak counts weeks that met the session *target*; the app (both tabs)
    has always counted any week with a workout, so the copy was corrected
    (en, ar), and adherence is named as the figure that uses the target.
    **Tested:** 20 straight weeks read 20 on "1M" (it read 5); a ten-week
    run before the range is the longest (it read 1); both old figures
    reproduced by running the new tests on the old code.
  - **Fixed: the volume sparkline dipped at both ends.** Its eight-week
    window started at today minus 56 days, mid-week, so the oldest point
    held part of a week (a 150 kg week read 50); and its last point was
    the week in progress, low until the week ends, so the line fell every
    Monday. The window now starts on the first day of the week eight weeks
    before this one (the day chosen in Settings), and the line is the
    eight finished weeks; this week's figure is the headline beside it.
    The line is not drawn while those weeks are all zero (a first week of
    training drew a flat line along the bottom). The week card's other
    figures and "No training in the last 8 weeks" are unchanged, apart from
    that window now reaching back to the start of its oldest week.
    **Tested:** a whole first week (both its ends in, the day before out),
    this week left out, no line for a first week, Saturday weeks; all four
    failed on the old code. **Not checked:** on the phone.
    **Fixed after CI, 2026-11-11:** in a zone with daylight saving the line
    still had nine points, a zero first: the window starts at a local
    midnight, bucketed with today's UTC offset, so across a clock change
    that midnight falls an hour into the day before, a week earlier. CI's
    America/Los_Angeles run failed on it; Windows runs could not show it.
    The series now keeps the last eight finished weeks (the extra one is
    always empty: the query starts at that instant). A new test builds the
    nine weeks by hand, so it fails in every zone on the old code.
  - **Fixed: the Est. 1RM tile showed the last session, not the best.** It
    took the most-logged lift's latest session against the one before it,
    so a light day or a deload read as a lower 1RM with a red arrow (any
    0.5 kg drop), and Progress gave the same lift another number. The tile
    now shows the main lift's best estimate over the last three months
    (Progress's default range), against the best before them; under 2.5%
    either way it is flat, the threshold Progress's insights use. No arrow
    without an earlier best, or when the only comparison is the lift's
    first session (Progress words that as "since your first session").
    After three months without a lift, the main lift's all-time best, no
    arrow. Built from Progress's own providers (`loggedExercises`,
    `strengthChange` for 3M and all time); the rule is
    `pickStrengthHeadline` in `dashboard/domain/strength_headline.dart`.
    "Main lift" is now Progress's: most *sessions*, where the tile counted
    sets, so with uneven set counts the tile may name a different lift than
    before, the one Progress's lift chart opens on. Removed:
    `WorkoutDao.watchMostLoggedExerciseOneRM`, `MostLoggedOneRM` and their
    three tests. **Tested:** the rule (lift choice, the threshold both
    ways, no earlier best, first session, after a break) and the provider
    on a real database (a deload keeps 150 kg and an up arrow where the old
    tile showed 110 kg down; -1.3% is flat; a break shows the all-time
    best). **Not checked:** on the phone.
  - **Fixed: "Same point last week" lagged behind the clock.** Its cut-off
    (now minus seven days) was fixed when the query was made, and the
    provider is only remade when `localNow` changes (noon, 18:00,
    midnight). At 09:00, after saving a workout, Home still compared with
    last week up to 07:00, so a workout from 07:30 last week was left out
    and the badge read higher than it should. `watchVolumeBetween` now takes
    the cut-off as a function and reads it again on every write to the
    workouts table, so it is current whenever this week's figure changes.
    It listens before its first read, reads one at a time and drops repeat
    totals. Between writes the cut-off still moves only with `localNow`:
    with nothing saved, a workout from last week can join the comparison
    up to six hours late; this week's figure is not moving then. **Tested:**
    saving at 09:00 moves the cut-off past a 07:30 workout (it read 0 with
    the old fixed cut-off, run to check); the stream re-reads its bound on
    each write and skips repeats. **Not checked:** on the phone.
  - **Fixed: the week card failed with its optional figure.** The snapshot
    awaited the same-point figure with the two series the card is about, so
    an error in that one query showed "Could not load this week". Worse,
    Riverpod 3 retries a failed provider and keeps its `.future` pending
    while it does, so the card first sat loading through every retry. The
    snapshot now reads that figure's state: it waits only for a first load,
    and on an error it builds without it (no badge, "Last week X"), logged
    through `reportError` (debug builds only). **Tested:** the provider
    with the figure failing (it hung until the 30 s test timeout on the old
    code) and the page (the old code showed "Could not load this week").
    **Not checked:** on the phone.
  - **Open, app-wide, not changed:** Riverpod 3's automatic retry applies
    to every provider. A query that fails shows its card loading through
    the retries (riverpod 3.4.3 `ProviderContainer.defaultRetry`: up to 10
    retries for an exception, 200 ms doubling to a 6.4 s cap, about **38 s**
    in all; seen again in the Workouts tab's programs row) before the
    error and its Retry button appear. Whether to turn retry off for
    local Drift queries (which do not fail transiently the way a network
    call does) is a decision for the whole app, in `ProviderScope`.
  - **Changed: two taps lead where they point.** The "Last workout" row
    opens that workout's detail page (it opened the Workouts tab, where it
    had to be found again); with none yet it still opens the Workouts tab.
    The body-weight tile opens the weigh-in history, which also logs one
    (it opened the top of Progress, with the body chapter at its far end).
    The week card, "See all" and the other three tiles still open
    Progress, where their figures are explained. "Start from a program"
    still opens the Workouts tab and its programs row; starting a program
    from Home would need a picker, new work and not a fix. **Tested:** both
    taps (each failed on the old code). **Not checked:** on the phone (see
    the next line).
  - **Checked on the phone, 2026-11-11** (debug build of `d292027`, the
    owner's real data in the debug copy: Arabic, weeks from Saturday,
    target 3): the sparkline is eight finished weeks with the break as its
    dip; the day strip runs Saturday first, right to left, today ringed;
    "Same point last week: 9,830 kg" against 0 kg on a Wednesday morning
    (a true like-for-like ↓100%; see the open question below); Est. 1RM
    47 kg for Face Pull, the most-sessions lift, with no arrow (its only
    comparison is its first session); streak 2 weeks on Home and Progress;
    Progress's longest streak 4 weeks on both "3M" and "1M" (it was cut to
    the range before); the explainer's new wording, in Arabic; the last
    workout row opens 4 Nov's workout, the body-weight tile the weigh-ins.
    **Seen, not changed:** the Est. 1RM tile's Arabic title is ellipsized
    ("الوزن التقديري لأقصى تكرار…"); the average-duration tile reads
    14 min while the last workout was 58 min, which looks like short
    durations in the imported data, not checked further. **Open question
    for the owner:** with nothing yet this week, the badge is a red
    "↓100%" whenever last week had trained by the same point; correct, but
    it reads as a failure on a rest morning (answered the same day: keep
    it). **Not checked:** TalkBack.
  - **Refactor: `dashboard_page.dart` split, as Progress was.** 1,116
    lines and 20 widgets became the page (scaffold, greeting, wide rows;
    140 lines) and four files in `dashboard/presentation/sections/`:
    `today_card.dart`, `week_section.dart`, `progress_section.dart` and
    `recent_section.dart`. Their four entry widgets are public
    (`TodayCard`, `ThisWeekSection`, `ProgressSection`, `RecentSection`);
    everything inside them stays private. The code was moved, not
    rewritten: sorted line by line, old and new differ only in the
    `super.key` the now-public constructors take. The week badge's rule
    left the widget for `WeekSnapshot`: `comparedWithKg`, `volumeChange`
    and `volumeChangePercent`, each unit-tested; the badge reads them and
    behaves as before. **Tested:** every existing Home test passes
    unchanged, and five new tests cover the rule.
  - **Removed: dead code for a Library card Home no longer has.**
    `dashboardLibrarySummaryProvider`, `ExerciseDao.watchLibrarySummary`
    (a watched `SELECT` of the whole exercise table) and `LibrarySummary`
    were read by nothing in `lib/`; their two tests went with them, the
    only thing that used them. Nothing on screen changes.
  - **Owner's decision on the week badge:** keep showing the real status,
    "↓100%" included, when nothing is logged yet this week; it is not to
    be hidden until the first workout.
  - **Added: the week card says when there has been a break.** With
    neither this week nor last week trained, the card had no badge (both
    zero) and no caption (last week's total zero): a break of two to seven
    weeks left it silent ("No training in the last 8 weeks" only comes
    after eight). It now reads "No workouts for N weeks" (new string,
    en/ar with Arabic plurals), N counting the empty weeks in a row, this
    one included (`WeekSnapshot.weeksWithoutWorkouts`). Counted by
    sessions, not volume, so a week of timed sets only is not a break.
  - **Fixed: the badge's percentage has a ceiling.** Past 999% it reads
    "999%+" (`WeekSnapshot.maxShownChangePercent`): a first workout against
    a few kilos at the same point last week read "14900%".
  - **Fixed: the session goal showed 3 before the real target.** The
    target was read as the profile's `.value`, so the card showed the
    default "x / 3" until the profile arrived. The card now waits for the
    profile (it shows its loading state); a profile that fails to load
    falls back to `defaultWeeklySessionTarget`, Progress's constant, instead
    of a second literal 3. **Tested:** the break count (a break, this week
    only, back this week, nothing in the window, timed sets), both
    languages, the caption on the page, 999%+ and 999%, the goal while the
    profile is loading. Not run on the old code: the tests use the new
    field and string. **Not checked:** on the phone.
  - **Changed (owner's choices): the start card and the fourth tile.**
    - The start card's caption says how long ago, in calendar days: "Last
      workout: 7 days ago" (today / yesterday / N days ago; new plural
      string `dashboardDaysAgo`, en/ar). It gave the date, which the
      Recent row under it also gives. Days are counted on dates, not
      hours (`calendarDaysBetween`, on UTC dates so a clock change cannot
      lose a day). Progress's hero keeps its date.
    - The bolt icon beside the start card's headline is gone, and with it
      the play arrow it became during a workout; the "IN PROGRESS" label
      already says that.
    - The "Average duration" tile is now "This month": finished workouts
      since the 1st (`WorkoutDao.watchFinishedWorkoutCountSince`, one
      `COUNT`), opening the Workouts tab. The all-time average barely
      moved and read 14 min beside a 58-minute last session with the
      owner's imported data. Removed with it:
      `dashboardAverageWorkoutDurationProvider`,
      `WorkoutDao.watchAverageDurationSeconds`, its two tests and the two
      strings. **Tested:** the count (finished only, the 1st included),
      the tile starting again on the 1st with the app open, calendar days
      (same day, across midnight, a week, a month boundary, clock-change
      weekends), both languages, and the page (tile titles, caption, no
      icon). **Not checked:** on the phone.
  - **Changed: Home for someone who has never finished a workout.** It was
    five empty states at once: "No training in the last 8 weeks" (implying
    some before) with a caption about "older history", three tiles each
    asking for a workout, and a "Last workout: Nothing yet" row. Now the
    week card reads "Your first week starts here" (new string, en/ar) above
    the goal and the day strip; Progress shows only the body-weight tile,
    full width (a weigh-in needs no workout); Recent is gone unless a timer
    has been used. One signal decides it, `dashboardIsNewUser` (from
    Progress's `firstWorkoutAt`, the first finished workout), false while
    loading or on an error so a returning user never sees the welcome
    flash by. **Tested:** someone new (fails on the old code), new with a
    timer used (fails on the old code), and back after 90 days (unchanged:
    the old wording and all four tiles). **Not checked:** on the phone
    (the debug copy has workouts, so the welcome cannot show there).
  - **Checked on the phone, 2026-11-11** (debug build of `0ec3bd1`, the
    owner's data): the start card reads "آخر تمرين: قبل 7 أيام" (4 Nov
    to 11 Nov) with no icon beside the headline; "This month" reads one
    session, matching the history's single November workout, and opens
    the Workouts tab; the week badge's 9,830 kg is 31 Oct (3,075 kg) plus
    4 Nov (6,755 kg), last week from Saturday to the same moment. Not seen
    on the phone: the break caption, "999%+" and the welcome, which this
    data does not produce.
  - **Performance: the start card no longer rebuilds while a workout is
    typed in.** It watched the whole draft, which changes on every weight
    and rep entered, while the workout page sits on top. It now selects
    the two numbers it shows (`draftCounts`: exercises and completed
    sets, a record compared by value), so it rebuilds only when a draft
    opens or closes, an exercise is added or removed, or a set is ticked.
    Nothing on screen changes. **Tested:** the selection hears ticking,
    not typing (`draft_counts_test.dart`). **Reasoned, not tested:** that
    the card uses it, from the code. This was the last of the twelve Home
    review items.
- Changed 2026-11-10, Progress tab (reviewed, then fixed one item at a
  time; commits `a6c7e51`..`ecb2ac0` on `recovery/2026-10-22`). **Not in the
  1.0.4+5 bundle**, which was built from `eafe670` before any of it: the
  next upload needs versionCode 6.
  - **Wrong figures fixed.**
    - Strength change compared the latest session with every earlier one,
      so any session that was not a new best read red. It is now the
      range's best against the best from any time before the range. A lift
      with nothing before the range is compared with its first session in
      it, and the row says "first session: X" and the insight "… since
      your first session" (owner's decision). Copy in both languages.
    - 1RM record dots were judged inside the visible range, so every
      chart's oldest point was a "record"; they are judged against all
      history now. The chart also silently kept only the newest 50
      sessions; it keeps all of them.
    - "Per week" divided by the calendar weeks a range touches (a 14-day
      range is usually three); it divides by the range's length. The week
      in progress no longer counts as a missed target from its Monday, and
      the insights ignore it.
    - A break inside the range now counts: someone who trained before the
      range is averaged over all of it, and a range with nothing in it
      after a break shows zero weeks and "Last workout: …" instead of the
      new-user empty states (`watchFirstWorkoutAt`, `watchLastWorkoutAt`,
      `fillEmptyRange`).
    - Range windows, body weight and the weekly target went stale while
      the tab stayed open; they follow `localNowProvider` and the data.
    - Effort is averaged per rated set, like rest.
  - **Clearer page.**
    - One heading per section: the large chapter headings are gone (the
      pinned tabs name the chapter; screen readers still get a header).
    - The personal-records insight is removed (it repeated the hero), and
      the strength insight needs a 2.5% change, worked out from Epley (one
      more rep is 1/(30+reps)).
    - Value axes are round in the reader's unit (pounds included), and the
      weekly bar charts have one.
    - A 0% change reads "unchanged".
    - The lift picker is a searchable sheet of logged lifts.
  - **Code.** Scrolling and logging no longer rebuild the whole page;
    calculations live in `domain/` with tests; the 2,690-line page is split
    into chapter libraries (docs/widgets.md).
  - **Checked on the SM N970F (debug copy)**, Arabic: light and dark,
    kilograms and pounds, and with the owner's real data imported. That
    check found two bugs, both fixed: the volume-trend insight went silent
    on "Year" because empty weeks before the first workout filled its
    earlier half, and two screen-reader faults (the lift picker could not
    be pressed, axis ticks were read as bare numbers).
  - **Real data in dark mode and pounds, checked the same day:** every
    chapter reads correctly. It found body weight shown as "207.23 lb"
    (94 kg converted, a precision no scale has): body weight now shows at
    most one decimal in either unit (`UnitFormatters.bodyWeight`) on
    Progress, the Home tile, the measurement rows and Personal details.
    The 1RM chart's tooltip said "96.25 kg" under a "96 kg" headline; it
    is rounded like the headline now.
  - **Not checked:** TalkBack gestures and reading order (only the labels
    it would read).
  - **Found on Home with the same data, then fixed (owner's choice):** on
    a Tuesday with no workout yet, this week's volume read "0 lb ↓100%",
    because the badge compared this week so far with all of last week and
    was red from every Monday. It now compares with last week up to the
    same moment (`watchVolumeBetween`, `dashboardLastWeekToDateVolume`),
    and the caption says "Same point last week: X" ("في مثل هذا الوقت
    الأسبوع الماضي"). With nothing by that point last week there is no
    badge and the caption is last week's total. Seen on the phone: the
    caption reads 3,075 kg, last Tuesday's volume by the same hour, where
    the badge was measured against the whole week's ~9,800 kg. The
    "same moment" follows `localNowProvider`, so it can lag by a few
    hours.
- Changed 2026-11-05, Progress tab:
  - **Wrong data fixed.** Effort, rest, session volume and weekly-by-muscle
    were tables that printed the first 8 or 12 rows of an oldest-first
    query, so a three-month view showed the sessions from three months ago
    and never the newest. They are charts over every session now. The
    smoothed lines no longer dip below real values
    (`preventCurveOverShooting`), a series of equal values is drawn
    mid-chart instead of on the bottom edge, and axis dates no longer
    overprint in Arabic. Muscle-group names and the insight's exercise name
    are translated.
  - **Layout.** The range and four chapter tabs (Strength, Volume, Habits,
    Body) are pinned above the scroll view; a tab scrolls to its chapter and
    follows the reader. Est. 1RM and session volume share one card with a
    switch, as do effort and rest; tapping a muscle group shows its weeks.
    New shared control: `SegmentedPills` (docs/widgets.md).
  - No query, provider or schema changed. Review pictures of the whole
    page: `flutter test test/golden/progress_review_golden_test.dart
    --update-goldens --run-skipped`, output in `build/progress_review/`.
  - **Not done:** a per-session value is now reachable by touch (tooltip)
    and summarised for screen readers (latest, lowest, highest), but is no
    longer listed row by row. Weekly bar charts still have no value axis
    (done 2026-11-10, with the same screen-reader summary).
- Changed 2026-11-05, Home tab:
  - **Figures.** The Est. 1RM tile printed two decimals ("96.25 kg") where
    Progress shows the same estimate as "96 kg"; it is rounded the same way
    now. A timer shorter than a minute read "0m"; timers show mm:ss.
  - **This week.** The session count was on the card three times (goal,
    day checks, a "Sessions" stat). The stats row is gone: last week's
    volume sits under this week's, and the streak is a Progress tile. The
    goal is one segment per target session. The day strip marks today with
    a ring and draws days still to come as outlines, so they no longer look
    like missed days.
  - **Start card.** Its caption says when the last workout was; "Start from
    a program" is a text action instead of a second outlined button.
  - **Progress.** Two rows of two tiles (Est. 1RM, body weight, streak,
    average duration) in place of two tiles and a lone full-width one.
    (The average duration became "This month" on 2026-11-11.)
  - No query or provider changed. **Not checked:** tablet width on a
    device; TalkBack.
- Changed 2026-11-05, Workouts tab:
  - **Programs are one row of cards** that scrolls sideways (name and
    number of days), not a column of full-width cards. Three programs, the
    number the app ships with, took most of the first screen and left
    History two-thirds of the way down. The heading's explanation shows
    only while there are no programs. The built-in descriptions, which
    repeated the name, are no longer on the cards (they are on the
    program's page).
  - The Start button carries the same plus icon as the dashboard's.
  - **Large text:** a month heading's summary ran off the screen when the
    two halves did not fit on one line; it wraps now. A history title's
    "+N" pill is dropped when the row is too narrow to hold it. Both found
    by a test at 1.6x text.
  - History rows, the calendar and both import menus are unchanged.
    **Not checked:** many programs on a device; tablet width.
- **Version 1.0.5 (versionCode 6), 2026-11-10.** Bumped for the next Play
  upload: the Progress review series and the fixes after it (`a6c7e51`..
  `21560ad`, listed above), and Home's week badge. Whether 1.0.4+5 was ever
  uploaded is not recorded here; 6 is higher than either. Merged to `main`
  with PRs #2 and #3. Build with `scripts/build_android.sh bundle`; keep
  `build/symbols/1.0.5+6` with it. The same **before a wide rollout**
  points as 1.0.4 apply (image terms, a Play testing track on a phone).
- **Version 1.0.4 (versionCode 5), 2026-11-05.** Bumped for the next Play
  upload: exercise pictures and the picture swiper, the Progress, Home and
  Workouts restyles, and the fixes listed above since 1.0.3. Build with
  `scripts/build_android.sh bundle`; keep `build/symbols/1.0.4+5` with it.
  **Before a wide rollout:** read the ChatGPT and Gemini terms for the
  three exercise pictures (ASSETS-LICENSE.md), and try the build from a
  Play testing track on a phone, since a locally signed build cannot
  update the Play install.
- **Parked by the owner, 2026-11-05:** "EZ bar wide-grip upright row" is
  not in the catalogue (only the narrow-grip Upright Row). The programme
  workbooks list "Wide Grip BB Upright Row (last resort)" as an
  alternative. Proposed and not started: add "Wide-Grip Upright Row" as a
  fourth exercise written for the app.
- **Open, found 2026-11-05:** in Arabic, the Library list shows equipment
  in English ("Bodyweight", "Machine") in each row's subtitle; the detail
  sheet translates it.
- Fixed 2026-11-03: the dashboard greeting, date and week windows went stale
  while the app stayed in memory (seen on the phone as "Good evening, Friday
  30 Oct" on Tuesday 3 Nov morning). They now follow `localNowProvider` /
  `todayProvider` in `core/services/clock.dart`. The Tracker calendar's
  visible month, "today" ring and history-row highlight had the same
  pattern and use the same providers now. **Not audited:** other
  `DateTime.now()` reads in Progress and body-metric widgets. (Progress's
  were fixed 2026-11-10: every range query takes its window from
  `progressSinceProvider`. The body-metric editor's default date is still
  read when it opens, which is what it should be.)

Checked 2026-09-20, not copied from old notes:

- `flutter analyze --fatal-infos --fatal-warnings`: **no issues**.
- `flutter test`: **438 passed, 1 skipped, 0 failed** (the README's 423 was stale).
- `targetSdk` resolves to **36** with the installed Flutter 3.47.5, which meets
  Google Play's Aug 31 2026 requirement for new apps.
- The app is feature-complete. What is missing is **release plumbing**, one
  timer gap, and an untested accounts backend. Nothing else in the old plan
  blocks a first release.
- `supabase.json`, `android/key.properties` and the upload keystore were
  missing on 2026-09-20 (the app was originally built on a Linux server and
  these files are gitignored). **Update 2026-09-21:** all three are now on
  this machine. The keystore is the original key (alias `fittrack_upload`,
  created 2026-08-26); the properties file arrived as `key.properties.txt`
  and was renamed, because Gradle reads only `key.properties`.
- No physical device is attached. **Update 2026-09-21:** the `atco_test`
  emulator cannot boot on this machine either: its AVD definition exists but
  the Android 35 `google_apis` x86_64 system image is not installed, and
  there are no `cmdline-tools` to install one. C6 and S1 need either that
  SDK download (about 1.5 GB) or a physical Android phone over USB.
  Everything timer- and notification-related has so far been seen on an
  emulator on another machine only.

## The one constraint code cannot remove

A personal Play developer account created after 13 Nov 2023 must run a
**closed test with at least 12 testers opted in for 14 continuous days**
before it may apply for production access
([Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465)).
Organisation accounts and older personal accounts are exempt.

So "finished in two days" means: **signed build, listing, policy pages and
the closed test all live by the end of Day 2.** Public availability is then
14 days plus Google's review away. If Day 2 ends with 12 testers opted in on
Tue Sep 22, the earliest production application is Tue Oct 6.

- [ ] **me** First thing: open Play Console and note the account type and its
      creation date. If it is an organisation account, or a personal account
      from before 13 Nov 2023, the 14-day wait does not apply and this plan
      ends in a production release after Day 2 plus review.

## Decisions (defaults apply unless you say otherwise)

| # | Decision | Default | Why |
|---|---|---|---|
| D1 | iOS | **Not in v1** | No Mac, no $99 enrolment, CI iOS job never run |
| D2 | Telemetry / crash SDK | **None** | Privacy policy and listing already say "none"; Play Console *Android vitals* gives crash rates |
| D5 | Web | **Not a launch target** | Persistence never verified |
| D6 | Accounts at launch | **Keep them**, gated on the Day 1 end-to-end test (C4) | Fallback below |
| D7 | `USE_EXACT_ALARM` | **Keep** | Timer apps are an accepted use; if Play rejects it, delete the two manifest lines and alerts become inexact |

**D6 fallback.** If C4 is not passing by end of Day 1, ship v1.0 without accounts:
the release build hides Account, Backup and the welcome sign-in buttons, and
they return in 1.1. That is a scope cut and an ADR-8 change, so it needs your
approval before I touch code.

## Day 1 — make the build shippable

Lead-time items first; they cost calendar time, not effort.

- [ ] **me** **A0** On the Linux server, in the Ironyx checkout: run
      `git status` and `git log origin/main..HEAD --oneline`. Anything listed
      is work that GitHub (and therefore this machine) does not have; push it
      or tell me before we build on this checkout. Then copy the three
      gitignored things across, from a PowerShell in `F:\Ironyx` (not
      `F:\...` as the target: `scp` reads the drive letter as a host name):
      `scp USER@SERVER:~/Ironyx/supabase.json .` and
      `scp USER@SERVER:~/Ironyx/android/upload-keystore.jks android/` and
      `scp USER@SERVER:~/Ironyx/android/key.properties android/`
      (adjust the remote path). These carry passwords, so copy them with `scp`
      rather than pasting them into a chat. If the keystore is found, A3 is
      unnecessary; just back it up.
      *2026-09-21: `supabase.json`, the keystore and `key.properties` are
      here (the properties file needed renaming from `.txt`). Still open:
      the `git status` / `git log origin/main..HEAD` check on the server, and
      backing up the keystore and `key.properties` to two places.*
- [ ] **me** **A1** Create the Play developer account ($25) and start identity
      verification. This can take days. Everything in Day 2 that uses the
      Console waits on it.
- [ ] **me** **A2** Line up **15+ testers** with Gmail addresses (12 must stay
      opted in for 14 days; 3+ spare for drop-outs). Ask today so they can opt
      in on Day 2.
- [x] **me + dev** **A3** *Not needed: A0 found the original keystore
      (2026-09-21).* Only if A0 did not find the original keystore:
      generate a new upload key: `keytool` from
      `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\bin` (not on PATH),
      recipe in `SETUP.md` §5. You choose the passwords; they stay in the
      gitignored `android/key.properties`. **Back up `upload-keystore.jks` and
      `key.properties` to two places the moment they exist.** Losing the key
      means never updating the listing.

Code and configuration:

- [x] **dev** **C1** Timer end notification (done 2026-09-20, commit `c9ae406`).
      `_rescheduleBoundaries` scheduled only phase *starts*, so a locked phone
      went silent when the final interval ended. It now also schedules a
      "Timer complete" notification for the total end through a new
      `NotificationService.scheduleCompletion` (own id, the existing
      `timer_complete` channel), with English and Arabic strings. It is
      rescheduled on resume and skip, cancelled by `cancelAll` on pause and
      finish, and skipped without notification permission. Five new tests in
      `test/unit/timer_controller_test.dart`; four fail against the old
      controller. Analyze clean. **Still emulator/device-unverified:** the
      alarm actually firing while backgrounded is part of C6.
- [ ] **dev + me** **C2** Host the privacy policy and a delete-account page.
      **dev, done 2026-09-20 (commit `d3f36a9`):** `docs/_config.yml` (theme, and
      hides the internal docs), `docs/index.md`, `docs/delete-account.md`, and
      front matter on `docs/PRIVACY_POLICY.md`. **me, still to do, after the
      commit is pushed:** repo Settings → Pages → Deploy from branch → `main`
      → `/docs`. URLs then become `https://soshe90.github.io/Ironyx/privacy/`
      and `https://soshe90.github.io/Ironyx/delete-account/`. Open both in a
      browser before pasting them into Play Console; I could not render Jekyll
      locally, so the first load is the real test.
- [ ] **me** **C3** Supabase project, all four:
      1. Confirm the `backups` table and `delete_my_account()` exist (run
         `docs/cloud_backup_setup.sql` if unsure).
      2. Authentication → URL Configuration: add `com.soshe90.ironyx://login-callback`
         to Redirect URLs and move Site URL off `http://localhost:3000`.
      3. **Custom SMTP.** Supabase's built-in sender only delivers to your own
         team members and is capped at about 2 emails an hour, so sign-up and
         reset emails would never reach a tester. Fastest free route: Gmail
         with an app password (`smtp.gmail.com`, port 465, from
         `mustafa.salih15@gmail.com`; needs 2-step verification on).
         Source: [Supabase SMTP docs](https://supabase.com/docs/guides/auth/auth-smtp).
      4. Copy the project URL and anon key into `supabase.json` (see
         `supabase.example.json`; gitignored).
      *2026-09-21 checked over the API with the new `supabase.json` (valid,
      gitignored, publishable key, URL matches the project). Project is
      reachable; email sign-in on, sign-ups on, **email confirmation
      required**. `backups` exists and **RLS is on** (an anonymous write is
      refused with 42501). **Not confirmed:** `delete_my_account()` — the
      anonymous lookup says "not found", which is also what a function that
      is hidden from `anon` can look like, so re-run
      `docs/cloud_backup_setup.sql` (idempotent) and check it in C4. Custom
      SMTP and the redirect URL are dashboard settings I cannot see.*
      Note: the privacy policy named Supabase as the only third party, and
      whichever SMTP provider you pick sends the emails. **dev, done
      2026-09-21:** `docs/PRIVACY_POLICY.md` now says sign-up and reset emails
      go through an email-sending service acting on our behalf (provider-neutral,
      so it stays true for Gmail or any other SMTP); "Last updated" is
      September 21, 2026.
- [ ] **dev + me** **C4** Accounts end to end on the release build (emulator is
      fine). Sign up → confirmation email arrives → tapping the link reopens the
      app signed in → Back up now → clear data → Restore → Forgot password →
      reset link → Delete account (and confirm the auth user is gone in the
      dashboard). About 1.5 h. **Decision point at 6 pm: if any step is still
      broken, invoke the D6 fallback.**
      *2026-09-21 split:* the **server half** needs no device and can be run
      by API once C3 is done: sign up a test address, confirm it by clicking
      the mailed link (the account confirms on Supabase's side even though the
      browser cannot open the `com.soshe90.ironyx://` redirect), sign in, write
      and read a backup as that user, call `delete_my_account`, then confirm
      sign-in fails and the `backups` row is gone. That proves SMTP, RLS and
      the delete function. The **app half** (link reopens the app signed in,
      Restore after clearing data, the reset-password screen) still needs a
      device. Code review of `SupabaseAuthService` and the deep-link wiring
      found no defect. Tester tip: open the confirmation link on the phone
      that has the app installed, or it cannot hand back to the app.
      Verification query for the delete function, to run after the SQL:
      `select prosecdef, has_function_privilege('authenticated','public.delete_my_account()','execute') as auth_can, has_function_privilege('anon','public.delete_my_account()','execute') as anon_can from pg_proc where proname = 'delete_my_account';`
      Expect `true / true / false`.
- [x] **dev** **C5** Signed bundle. `scripts/build_android.sh bundle`, then
      `keytool -printcert -jarfile <aab>` must show the upload key, not
      "Android Debug". Copy `build/symbols/<version>` somewhere durable (it is
      gitignored; without it that build's crashes cannot be read). Build release
      only with `supabase.json` present, or accounts are silently off.
      *Done 2026-09-21:* `build/app/outputs/bundle/release/app-release.aab`
      (87.7 MB, 1.0.0+1) is signed with the upload key (SHA-256
      `57:08:11:C8:EC:BF:DD:43:D2:0B:FA:FA:63:B0:80:62:5C:9A:57:05:2B:55:07:B3:C3:3A:BE:79:D7:F7:7D:90`,
      matching `fittrack_upload`). On this machine the build needs
      `scripts/build_android.sh bundle -P kotlin.incremental=false`, because
      the pub cache is on `C:` and the repo on `F:` (SETUP.md §6). The
      release APK from the same flags has the Supabase host compiled in, so
      accounts are on. **Still to do (me):** copy `build/symbols/1.0.0+1` and
      the keystore + `key.properties` to durable storage.
- [ ] **me + dev** **C6** Smoke test of the *release* build. On a physical
      device if you have one, otherwise the emulator; record results here.
      **Blocked 2026-09-21:** no working Android target on this machine (see
      "Where the app really stands"). The release APK is built at
      `build/app/outputs/flutter-apk/app-release.apk`; plug in a phone with
      USB debugging on, or approve the emulator image download, and the rest
      is `adb install` plus the checks below.
      - [ ] Cold start to dashboard, first launch after install (seeding 301
            exercises); note the time.
      - [ ] Log a workout, force-kill the app mid-workout, relaunch: draft
            restored.
      - [ ] Timer (Tabata): background, then lock the screen; phase alerts
            arrive on time and the **end notification arrives** (C1). Deny
            notification permission once and confirm the timer still works.
      - [ ] Export then import round trip; Delete all data then relaunch.
      - [ ] Arabic (RTL), dark mode, and 200% font scale on Dashboard and
            Active workout: no clipped digits.
      - [ ] TalkBack: 10 minutes on Active workout and Timer.
      *2026-09-29, automated on the LMR LX9 (Android 12) over USB with
      `scripts/run_device_tests.sh` (debug build, 26 journeys in
      `integration_test/`, all passing). Covered: first launch seeds 301
      exercises in ~4.5–4.9 s; draft survives a simulated kill; timer
      alarms really queued with Android (3 boundaries + completion) and
      cleared on pause/end; 400 workouts / 6,400 sets export in ~0.4 s
      (4 MB) and import in ~2 s; Arabic, 200 % text and dark mode lay out
      without overflow. **Found and fixed:** the timer never finished on a
      real device (just_audio's `play()` never completes at a clip's end, so
      the screen stayed open and the session was never saved), and the
      Delete-all dialog overflowed with the keyboard up. Both are in the
      working tree, **not** in the 25 Sep release APK. Still manual: the
      *release* build, a real force-kill, locked-screen alert timing,
      denied notification permission, TalkBack.*
      **Warning:** on 2026-09-29 an on-device test run uninstalled the
      release app and its data. Debug builds now use
      `com.soshe90.ironyx.debug`; run device tests only through the script,
      which refuses while the release app is installed.
      *2026-10-22: the SM N970F (Android 12) ran the debug-build workout
      journey: 9/9 passed, including immediate Finish after typing reps and
      two rapid Finish taps. The discard journey's old assertion was updated
      to the current immediate-discard/Undo behavior. This did not test the
      release build, real force-kill, locked-screen alerts, denied permission,
      export/import, Arabic layout or TalkBack; C6 stays open.*
      *2026-10-22 release-build check on SM N970F: `scripts/build_android.sh
      apk -P kotlin.incremental=false` built 1.0.2+3 with Supabase defines,
      release minification and 15 packaged native libraries confirmed stripped.
      The APK's upload-key signer SHA-256 begins `57:08:11:C8`, but the
      already-installed `com.soshe90.ironyx` 1.0.2+3 APK's signer begins
      `5D:8A:EA:72` (checked with `apksigner` after pulling its base APK).
      Android cannot update an installed app with a differently signed APK;
      uninstalling would erase local data. Nothing was installed or cleared.
      Release runtime checks remain open until a separate device/emulator is
      available, or the owner confirms a verified backup and explicitly
      authorizes a destructive reinstall. The debug integration test is not
      a substitute for release-build testing.*

Day 1 exit: a release-signed AAB that passed C4 and C6, and testers lined up.

## Day 2 — store, upload, start the clock

- [ ] **me + dev** **S1** Screenshots: at least 6 phone screenshots via
      `adb exec-out screencap`, in the order in `docs/STORE_LISTING.md`
      (active workout, progress chart, program detail, data management,
      dashboard, library). English light and dark; an Arabic set of at least 4.
      Populate demo data first so charts have a trend.
- [ ] **dev** **S2** Feature graphic, 1024×500 (Pillow is installed): brand
      navy `#0B1628` and teal `#38D6C0`, the icon, and 2 or 3 of the
      screenshots. You approve before upload. The 512×512 icon for Play is
      `assets/branding/ironyx-icon-512-opaque.png` (the other two masters
      have transparent corners; do not upload them).
- [ ] **me** **S3** Play Console: create the app (Free, Health & Fitness) and
      fill the forms. **dev, done 2026-09-21:** the exact answers are a
      form-by-form table in `docs/STORE_LISTING.md` ("Play Console answers"),
      with `(verify)` wherever it names a console label from memory; the
      "delete your account" sentence is already in the description, gated on
      C4. Target audience is recommended as **18 and over**, not "13+", to stay
      out of the Families policy; say if you want otherwise. The inputs are:
      - Listing text from `docs/STORE_LISTING.md`, plus the one line it
        recommends adding: *"You can delete your account and cloud backup from
        inside the app."*
      - Privacy policy URL and account-deletion URL from C2.
      - **Data Safety:** email and password (Supabase Auth); with backup, the
        training database as health and fitness data; encrypted in transit;
        deletable in-app and by request; nothing sold or shared for ads.
      - Health apps declaration; IARC questionnaire; target audience "not
        directed at children under 13"; ads: none; app access: no login
        required.
      - **Exact alarm declaration:** core function is the interval/rest timer
        firing phase-change alerts while the app is backgrounded.
- [ ] **me** **S4** Upload the signed AAB to a **Closed testing** track, add
      the tester list, roll out, and send the opt-in link. Testers must opt in
      *and* install; the 14-day clock needs 12 of them staying opted in.
- [ ] **dev** **S5** Docs: update `README.md` (status, 438 tests, pointer to
      this file), `docs/STORE_LISTING.md` status line, and commit.
      *2026-09-21: README, STORE_LISTING, SETUP and the privacy policy are
      updated in the working tree. Not committed or pushed yet; the Pages
      toggle in C2 needs the push.*

Day 2 exit: build in closed testing, 12+ testers invited, policy pages live.

## After Day 2 — waiting time, not work

- **Days 1–14 of the closed test:** keep 12+ testers opted in; read Play
  Console → Android vitals and tester feedback; fix real bugs and upload
  1.0.x to the same track (versionCode must increase).
- **About Oct 6:** apply for production access; Play asks about the testing
  you did, so answer with real feedback.
- **Then:** Google's first-release review (can take several days). Only after
  it is live: announce it, following each community's self-promotion rules.

## Deliberately not in this plan

Each of these was in the archived plan. None is needed for a first release,
and none should be started before the closed test finishes:

iOS and TestFlight, web build QA, Sentry or any analytics, landing website and
newsletter, Product Hunt and Reddit launches, blog posts, golden-image
refresh, coverage targets, performance profiling beyond the C6 stopwatch check,
the 12-week time-tracking table, per-table cloud sync, premium and in-app
purchases, the `WorkoutXlsxImportService` per-row duplicate query, the
unreproduced A2.14 delete-all race, and the "remove local data on sign-out"
question.

## Product research backlog — 2026-10-22 (not part of the two-day finish)

Read-only market and repo review. **No feature below is approved for implementation.**
Finish C4/C6 and the closed test before expanding scope; use tester evidence to
choose one improvement at a time. Sources describe competitor *claims*, not
hands-on verification. US advertised prices are not verified checkout prices.
The store listing is still a draft, not proof of actual users or positioning.

### Current product and positioning

- **Verified in repo:** unpublished, Android-first offline strength-training
  log: five areas (Home, Tracker, Library, Timer, Progress); sets/reps/weights,
  reusable programs, 301 seeded exercises, progress charts, English/Arabic,
  versioned export/import and optional account/manual one-slot cloud backup.
  Local SQLite is the source of truth; backup/restore **is not sync**
  (`README.md`, `docs/ADR.md` ADR-1, 3, 7, 8).
- **Assumed audience, to validate:** adults following repeatable lifting plans
  who want fast set entry, previous-session context and reliable gym-time use
  without a network or mandatory account. No customer research establishes the
  segment size, retention, willingness to pay or reasons to switch.
- **Proposed positioning, not approved store copy:** “Ironyx is a focused
  workout log for lifters who want to follow their plan, record every set, and
  understand their progress—even without a connection. Training stays on your
  device by default, with export and optional manual backup under your
  control.” Never imply automatic protection, multi-device sync, AI coaching,
  iOS/web support at launch, or exclusive Arabic/offline capabilities.
- **Verified limitations:** C4 still needs the real account/backend journey;
  C6 still needs release-build device checks; S1 needs store screenshots.
  Account backup contains training and profile data, is manual and last-write-
  wins; restore replaces local user data. Gzip is not client-side encryption.
  Uninstalling without a file export or successful backup can lose history.
  Web persistence and iOS operation are unverified (`docs/ADR.md`, `SETUP.md`).
  CSV program import has a specified format; XLSX history import targets a
  particular workbook layout, not arbitrary competitor exports (`README.md`).

### Competitor watchlist and source notes

Checked 2026-10-22: public US store listings, official pages and displayed
reviews. Product descriptions, UI imagery and release notes are developer
claims; no competitor app was installed. Prices, offers, review selection and
features may change by region/date. **Do not claim “only offline” or “only
Arabic”: Hevy lists Arabic, and Hevy, Alpha Progression and Boostcamp advertise
some offline logging; FitNotes is already free and ad-free on Android.**

| Comparator | Relevant offering / AI evidence | Advertised US price and recent update | Evidence |
|---|---|---|---|
| Strong (direct) | Focused routines, previous workouts, timer, charts, Watch, sync; no native-AI claim established | Free unlimited workouts/3 custom routines; Pro $4.99/mo or $29.99/yr advertised (other purchase entries exist). iOS 6.5.1, Oct 8: sign-in/sync fixes | [App Store](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577) |
| Hevy (direct/social) | Sets, routines, charts, friends, desktop/watch, advertised offline; Trainer guidance has unverified generation method; **iOS lists Arabic** | Pro entries include $2.99/mo, $23.99/yr, $74.99 lifetime; another monthly entry exists. iOS 3.2.2 around Oct 21: notes update | [App Store](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350), [site](https://www.hevyapp.com/) |
| FitNotes (direct/lean Android) | Daily exercise → save sets → history, timer, routines, backup, CSV; no native-AI claim established | Core free/no ads; Play displays Oct 24, 2025 update; iOS not planned per developer | [Play](https://play.google.com/store/apps/details?id=com.github.jamesgay.fitnotes&hl=en_US&gl=US), [quick start](https://www.fitnotesapp.com/quick_start/), [FAQ](https://www.fitnotesapp.com/faq/) |
| JEFIT (broad planner) | Large exercise/program catalogue, Wear OS, charts; markets AI adaptive plans and weight/rep suggestions, quality/method unverified | Basic free; Elite $12.99/mo or $69.99/yr in US listing. Play Oct 10: Wear OS timer/timed sets | [Play](https://play.google.com/store/apps/details?id=je.fit&hl=en_US&gl=US) |
| Alpha Progression (guided) | Account-free logging/manual plans; performance-based recommendations and generated plans are Pro. Existing plans/recommendations advertised offline; new plan generation needs network. Generative-AI claim **not** established | Pro regular US $12.99/mo or $79.99/yr. iOS 7.7, Oct 6: additional CSV export routes | [site/FAQ](https://alphaprogression.com/), [App Store](https://apps.apple.com/us/app/alpha-progression-gym-tracker/id1462277793) |
| Boostcamp (program-first/indirect) | Free program library, tracker; markets questionnaire “AI coach”, Pro auto progression, offline workouts; AI method unverified. Official and store library counts disagree | Pro $59.99/yr or $14.99/mo advertised. iOS 266, Oct 2: auto progression and alternatives | [Pro](https://www.boostcamp.app/pro), [App Store](https://apps.apple.com/us/app/boostcamp-workout-tracker/id1529354455) |

**User-review signals, not prevalence or verified current defects:** a 2023
[Strong review](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577)
requested flexible exercise types; a 2024
[Hevy review](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350)
reported tedious backdated-workout entry; a 2025
[Boostcamp review](https://apps.apple.com/us/app/boostcamp-workout-tracker/id1529354455)
reported a finish-workout freeze. Boostcamp's older offline complaint has a
2024 developer reply saying offline mode was added: **do not** call offline
absence a current defect. No specific recurring FitNotes complaint was
substantiated by the displayed reviews. Review samples do not prove a market
trend. Competitor UI conclusions are limited to official descriptions/images,
not measured usability or task completion.

### Prioritized findings and validation gates

- [ ] **me + dev — launch gate (C4/C6/S1, not new scope):** verify sign-up,
      confirmation, manual backup/restore, recovery and deletion against the
      live backend; review live RLS, data access/retention and account deletion
      before strengthening privacy claims. Smoke-test the release APK on a
      physical Android device, including real kill/resume, airplane mode,
      background/locked timer, denied permission and TalkBack. Capture *real*
      populated Library, data-management, light/dark and Arabic/RTL screens.
      The `test/golden/` files are skipped review fixtures: Library is loading,
      and Settings renders Arabic as replacement glyphs; neither proves
      real-device RTL quality. Preserve the D2 no-telemetry decision unless
      explicitly reconsidered with policy/listing updates.
- [x] **dev — P0, CSV import discoverability:** the Programs heading now has
      an always-visible options menu with a labeled CSV import item; the empty
      state still offers import. Widget tests cover both states and `README.md`
      describes the actual entry point. Code and tests verified locally
      2026-10-22; a manual device usability check is still worthwhile.
- [x] **dev — P0, CSV import validation and failure handling:** preview now
      names skipped unknown exercises, existing programs and malformed rows;
      invalid set counts are not silently defaulted. Apply failure is caught
      and reported without showing raw database errors. Unit and widget tests
      cover invalid input and forced write failure; CI-equivalent checks passed
      locally 2026-10-22. This is not a general spreadsheet migration tool.
      Large historical XLSX profiling remains deferred under the launch plan.
- [ ] **me + dev — P0 discovery:** run 8–12 consent-based Android usability
      sessions, including 4+ active Arabic users and people currently using
      rival loggers; compare first workout, repeat session, kill/resume,
      offline session, backup explanation and finding import. Observe task
      time, errors, corrections and return choice; do not collect unnecessary
      health data. Proposed gates: zero lost/duplicated sets in scripted
      recovery, every participant distinguishes local save from cloud backup,
      and no critical Arabic task failure. These are *targets*, not results.
- [ ] **dev + me — P1 candidate, select only after discovery:** make the
      already auto-persisted draft and last *successful* manual backup status
      legible; show backup date and replacement impact before restore. Problem:
      fear of lost data; competitors market sync/backup. Difference: explicit
      local/file/cloud provenance, not falsely reassuring “saved” after a
      failed write. Complexity **medium**; ongoing account-support/testing
      cost; risks are stale backups, false success, multi-device overwrites.
      Prototype copy and test users' understanding plus kill/network failures.
- [ ] **dev + me — P1 candidate:** refine existing “last time → today” set
      context instead of building a coach. Hevy shows past sets; Ironyx already
      displays them in `test/golden/active_workout.png`. Test speed, errors and
      visual clutter with a small optional display. Complexity **low–medium**,
      local-query maintenance; avoid comparing warm-ups, imported anomalies or
      different exercises as equivalent.
- [ ] **dev + me — P1 candidate, separate approval:** prototype explainable,
      optional progression prompts from sufficient comparable logged sets.
      Alpha Progression/JEFIT/Boostcamp already recommend targets; distinguish
      with inspectable source sets and user control, **not** “AI”. Validate
      comprehension and demand first. Complexity **medium–high**, local
      computation but substantial rules/tests; risks: misleading fitness
      guidance, sparse history, exercise equivalence and alert fatigue. No
      automatic plan edits or health/injury claims.
- [ ] **dev + me — P1 candidate, separate approval:** prototype one permitted
      source-format import with column/exercise/unit mapping, unmatched and
      duplicate preview, atomic apply and pre-import recovery. Strong and
      Alpha Progression offer CSV export; historical entry is a user pain,
      but no broad Ironyx importer exists. Complexity/support **high**;
      malformed files, memory, large-history query cost, unit and identity
      errors. Measure completed migrations and correction effort first.
- [ ] **dev + me — P1 candidate:** conduct bilingual device usability and
      accessibility passes across the *whole workout* (search, weights/units,
      timer, recovery), then fix measured RTL, mixed-numeral, typography,
      focus-order or clipping problems. Hevy already lists Arabic; quality,
      not exclusivity, must be proven. Complexity **medium** with recurring
      translation QA; test task time and error rate in both languages.
- [ ] **dev + me — P2 candidate:** optional factual weekly progress brief
      linking to underlying workouts, with explicit insufficient-data state.
      Competitors already offer charts. Complexity **medium**; SQL/index and
      multi-year profiling needed; avoid extrapolation or punitive streaks.
      Validate whether it helps users decide what to do next.

**Table stakes to protect:** fast editable set logging, previous performance,
programs, timer, search, interpretable progress, offline draft recovery and
portable history. **Avoid until evidence/approval:** social feed, AI/LLM health
coach or sensitive-data upload, automatic per-table sync, copying competitors'
branding/media/layouts or racing their program-library counts. Sync would
change ADR-8, conflict handling, privacy and operating costs: propose it
separately and obtain approval before any design or implementation. Reuse the
existing teal theme, five-tab navigation and focused workout UI; device-test
large text, keyboard and touch targets instead of reskinning from screenshots.

**Research exit:** after closed testing, compare whether users choose Ironyx
for a calmer, trustworthy repeat workout over the alternatives. If they
mainly need guided plans or social/community, do not build a shallow imitation.
Choose one proven problem, specify measurable success and maintenance cost,
then update the live plan before coding.

## Risks

| Risk | If it happens |
|---|---|
| Play account verification is slow | Day 2's Console steps slip; nothing before them does. Start A1 first |
| Gmail SMTP blocked or unreliable | D6 fallback: ship without accounts |
| Play rejects `USE_EXACT_ALARM` | Delete the two manifest lines; alerts arrive up to about 14 s late |
| No physical device | Timers and notifications stay emulator-verified only; treat the closed test as the real-device test and watch it closely |
| Upload key lost or not backed up | Listing can never be updated; do A3's backups immediately |
