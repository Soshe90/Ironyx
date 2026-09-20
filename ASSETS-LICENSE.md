# Asset licences

Every non-code asset shipped inside the Ironyx binary, where it came
from, and what its licence requires of us.

This file is enforced, not decorative: `tool/check_asset_licenses.dart`
runs in CI and fails the build if the exercise catalogue gains a source
that is not listed here, an image without a licence, an image hotlinked
from a third-party server, or an image file that ships without a
provenance record. (Known issue, 2026-09-20: on Windows the tool reports
every image as unreferenced because it compares `\` paths with the seed's
`/` paths; Linux CI is unaffected. Run it in CI, not locally on Windows,
until that is fixed.)

---

## Exercise catalogue and images

**Source:** [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
(browsable at <https://yuhonas.github.io/free-exercise-db/>)

**Licence:** [The Unlicense](https://unlicense.org/) — public domain
dedication. No attribution required, no share-alike obligation, cleared
for commercial redistribution.

**Covers:** all 301 exercises in `assets/data/exercises_seed.json` (seed
version 17, checked 2026-09-20; every entry carries a
`Public domain (Unlicense)` source record) — their names, instructions,
muscle and equipment classifications — and all 602 images in
`assets/images/exercises/free_exercise_db/` (two per exercise).

**Modifications:** images are resized to 600px wide and re-encoded as
JPEG at quality 80 to keep the download reasonable. Movement patterns
(`horizontalPush`, `hipDominant`, …) are our own classification; upstream
has no equivalent field.

We attribute anyway, in this file and in each exercise's `sources` record,
because "public domain" is a claim worth being able to substantiate later.

**To reproduce:** `python3 scripts/build_exercise_seed.py`

---

## Exercise demonstration videos

48 exercises carry a YouTube link in their `media` list. These are links
only — no video data is copied into or redistributed with the app, and
following one opens YouTube. Linking is not redistribution, so no licence
is required or claimed.

---

## Audio

**No audio files are bundled.** `assets/audio/` holds only a `.gitkeep`, and
is still listed in `pubspec.yaml` so that adding cues later needs no
manifest change. The timer's sound cues today call the operating system's
alert sound (`SystemSound.play` in `lib/core/services/timer_audio_service.dart`),
which ships with the OS, not with us.

If cue files are added, record their origin and licence here in the same
change. `tool/check_asset_licenses.dart` checks the exercise catalogue only —
it does **not** look at audio, so nothing enforces this.

---

## App icon, splash and brand artwork

`assets/branding/` (`ironyx-icon-1024.png`, `ironyx-icon-512.png`,
`ironyx-mark.svg`) and everything derived from it: the Android launcher
icons (legacy PNGs, adaptive foreground/background/monochrome vectors), the
Android and iOS splash marks, the iOS `AppIcon` set, the notification small
icon and the web icons. `assets/branding/` is source material and is not
bundled as a Flutter asset.

**Provenance is not recorded in the repository.** How the mark was made
(own design, commissioned, or generated with a tool) decides what can be
claimed about it and whether it can be trademarked, so the account holder
should add a line here saying which. Tracked in `TODO.md`, Week 0
("clearance").

---

## Fonts and icons

Material Icons and the Material Design font set ship with the Flutter SDK
under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
The `cupertino_icons` package (MIT) supplies the iOS icon font Flutter's
page transitions reference. Flutter surfaces both automatically in the
app's own licence page (the standard `showLicensePage` route), so no
additional attribution is owed. No other font files are bundled.

---

## Previously shipped, now removed

Recorded because "we used to ship this" is the question that matters if it
is ever asked.

Until seed version 10 the catalogue included images scraped from
**liftmanual.com** (49 hotlinked at runtime, 28 bundled as PNGs) and
**mybodycreator** (1 bundled PNG), all with `"license": null`. A further
set of bundled PNGs carried no source record at all. None of it was ever
licensed for redistribution.

All of it was deleted in the seed version 11 rebuild — the files are gone
from `assets/`, not merely unreferenced — and the catalogue was rebuilt
from free-exercise-db. Nothing from either site remains in the repository
or in any build produced from it.
