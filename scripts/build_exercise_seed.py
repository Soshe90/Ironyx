#!/usr/bin/env python3
"""Rebuild assets/data/exercises_seed.json from free-exercise-db.

Why this exists
---------------
The catalogue used to mix images scraped from liftmanual.com and
mybodycreator with a handful of public-domain entries. Those scraped
assets are someone else's copyright: fine in a personal build, a DMCA or
Play suspension once the app is published. This script rebuilds the whole
catalogue from free-exercise-db (Unlicense / public domain) so that every
shipped asset is legally ours to redistribute, and makes that rebuild
repeatable rather than a one-off cleanup nobody can reproduce.

    https://github.com/yuhonas/free-exercise-db

What it guarantees
------------------
* Every exercise carries a `sources` entry with a non-null licence.
  `tool/check_asset_licenses.dart` fails the build otherwise.
* Ids are preserved by display name. This is not cosmetic: `name` has a
  UNIQUE index, and `ExerciseDao.deleteOrphanedSeed` deliberately keeps
  any exercise a logged workout references. Minting a fresh id for a name
  that is still on disk would raise `UNIQUE constraint failed:
  exercises_table.name` during seeding — and only for users who have
  training history, which is the worst possible group to break.
* YouTube links from the previous seed survive on preserved ids. Linking
  is not redistribution, so they carry no licensing risk, and they are
  the one piece of curation free-exercise-db cannot replace.

Usage
-----
    python3 scripts/build_exercise_seed.py            # full rebuild
    python3 scripts/build_exercise_seed.py --dry-run  # report, write nothing

The upstream dump and the original images are cached under
scripts/.cache/ (gitignored), so re-runs are offline and fast.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SEED = REPO / "assets/data/exercises_seed.json"
IMAGE_ROOT = REPO / "assets/images/exercises"
FEDB_IMAGES = IMAGE_ROOT / "free_exercise_db"
CACHE = Path(__file__).resolve().parent / ".cache"

FEDB_JSON_URL = (
    "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
)
FEDB_IMAGE_URL = (
    "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"
)
FEDB_HOME = "https://github.com/yuhonas/free-exercise-db"

LICENSE = "Public domain (Unlicense)"
ATTRIBUTION = "Free Exercise DB (yuhonas)"

# Images are shipped at this width and quality. Upstream ships ~800px JPEGs
# at ~70KB; two per exercise across 251 exercises is ~35MB of APK, which is
# a real cost to install conversion. 600px/q80 lands around a third of that
# and is still sharper than the display size in the exercise detail sheet.
IMAGE_WIDTH = 600
IMAGE_QUALITY = 80

# free-exercise-db's muscle vocabulary onto the app's 11 muscle ids.
MUSCLES = {
    "abdominals": "core",
    "abductors": "glutes",
    "adductors": "legs",
    "biceps": "arms",
    "calves": "calves",
    "chest": "chest",
    "forearms": "forearms",
    "glutes": "glutes",
    "hamstrings": "legs",
    "lats": "back",
    "lower back": "back",
    "middle back": "back",
    "neck": "neck",
    "quadriceps": "legs",
    "shoulders": "shoulders",
    "traps": "traps",
    "triceps": "arms",
}

# ...and its equipment vocabulary onto the app's 10 equipment ids.
EQUIPMENT = {
    "barbell": "barbell",
    "bands": "band",
    "body only": "bodyweight",
    "cable": "cable",
    "dumbbell": "dumbbell",
    "e-z curl bar": "barbell",
    "exercise ball": "other",
    "foam roll": "other",
    "kettlebells": "kettlebell",
    "machine": "machine",
    "medicine ball": "other",
    "other": "other",
    None: "other",
}

CATEGORIES = {
    "strength": "strength",
    "powerlifting": "strength",
    "olympic weightlifting": "strength",
    "strongman": "strength",
    "cardio": "cardio",
    "stretching": "mobility",
    "plyometrics": "plyometric",
}

LEVELS = {"beginner": "beginner", "intermediate": "intermediate", "expert": "advanced"}

# free-exercise-db's "static" is our "isometric"; the rest match.
FORCES = {"push": "push", "pull": "pull", "static": "isometric", None: None}

MECHANICS = {"compound": "compound", "isolation": "isolation", None: None}

# Name fragments that imply a single-sided movement. Checked case-insensitively.
UNILATERAL_HINTS = (
    "one-arm",
    "one arm",
    "single-arm",
    "single arm",
    "one-leg",
    "one leg",
    "single-leg",
    "single leg",
    "one-legged",
    "alternate",
    "alternating",
    "concentration curl",
)


@dataclass(frozen=True)
class Pick:
    """One curated catalogue entry.

    `upstream` is the free-exercise-db display name — the join key, and
    the thing that breaks loudly if upstream renames something.

    `name` overrides the display name. Used to keep the app's own
    vocabulary ("Push-Up", not "Pushups") and, critically, to land on a
    name the previous seed already used so the row id is preserved.

    `pattern` is the app's `MovementPattern`. free-exercise-db has no
    equivalent field, the column is NOT NULL, and `Exercise.fromDrift`
    resolves it with `.byName()` — an unmapped value is a crash, not a
    blank, so every pick carries one explicitly.
    """

    upstream: str
    pattern: str
    name: str | None = None

    @property
    def display(self) -> str:
        return self.name or self.upstream


# --- The catalogue ---------------------------------------------------------
# 301 entries. Ordered by muscle group so the file reads like the library.
# Where a `name` override appears, it is usually there to preserve an id
# from the previous seed; see the module docstring for why that matters.

CURATION: list[Pick] = [
    # -- Chest ------------------------------------------------------------
    Pick("Barbell Bench Press - Medium Grip", "horizontalPush", "Barbell Bench Press"),
    Pick("Barbell Incline Bench Press - Medium Grip", "horizontalPush", "Incline Barbell Bench Press"),
    Pick("Decline Barbell Bench Press", "horizontalPush"),
    Pick("Dumbbell Bench Press", "horizontalPush"),
    Pick("Incline Dumbbell Press", "horizontalPush"),
    Pick("Decline Dumbbell Bench Press", "horizontalPush"),
    Pick("Dumbbell Flyes", "horizontalPush"),
    Pick("Incline Dumbbell Flyes", "horizontalPush"),
    Pick("Cable Crossover", "horizontalPush", "Cable Fly"),
    Pick("Low Cable Crossover", "horizontalPush"),
    Pick("Incline Cable Flye", "horizontalPush", "Cable Incline Fly"),
    Pick("Flat Bench Cable Flyes", "horizontalPush", "Cable Lying Fly"),
    Pick("Butterfly", "horizontalPush", "Pec Deck Fly"),
    Pick("Machine Bench Press", "horizontalPush", "Chest Press Machine"),
    Pick("Smith Machine Bench Press", "horizontalPush"),
    Pick("Pushups", "horizontalPush", "Push-Up"),
    Pick("Dips - Chest Version", "horizontalPush", "Dip"),
    Pick("Straight-Arm Dumbbell Pullover", "other"),
    Pick("Cable Chest Press", "horizontalPush"),
    Pick("Incline Cable Chest Press", "horizontalPush"),
    Pick("Standing Cable Chest Press", "horizontalPush"),
    Pick("Dumbbell Bench Press with Neutral Grip", "horizontalPush"),
    Pick("Dumbbell Floor Press", "horizontalPush"),
    Pick("Close-Grip Dumbbell Press", "horizontalPush"),
    Pick("Decline Dumbbell Flyes", "horizontalPush"),
    Pick("Incline Push-Up", "horizontalPush"),
    Pick("Decline Push-Up", "horizontalPush"),
    Pick("Push-Up Wide", "horizontalPush"),
    Pick("Single-Arm Cable Crossover", "horizontalPush"),
    Pick("Svend Press", "horizontalPush"),
    # -- Back -------------------------------------------------------------
    Pick("Barbell Deadlift", "hipDominant", "Deadlift"),
    Pick("Sumo Deadlift", "hipDominant"),
    Pick("Rack Pulls", "hipDominant"),
    Pick("Trap Bar Deadlift", "hipDominant"),
    Pick("Bent Over Barbell Row", "horizontalPull", "Barbell Row"),
    Pick("Reverse Grip Bent-Over Rows", "horizontalPull"),
    Pick("One-Arm Dumbbell Row", "horizontalPull", "Dumbbell Row"),
    Pick("Bent Over Two-Dumbbell Row", "horizontalPull"),
    Pick("Dumbbell Incline Row", "horizontalPull"),
    Pick("Lying T-Bar Row", "horizontalPull", "T-Bar Row"),
    Pick("T-Bar Row with Handle", "horizontalPull"),
    Pick("Seated Cable Rows", "horizontalPull", "Seated Cable Row"),
    Pick("Smith Machine Bent Over Row", "horizontalPull"),
    Pick("Inverted Row", "horizontalPull"),
    Pick("Wide-Grip Lat Pulldown", "verticalPull", "Lat Pulldown"),
    Pick("Close-Grip Front Lat Pulldown", "verticalPull"),
    Pick("Underhand Cable Pulldowns", "verticalPull"),
    Pick("V-Bar Pulldown", "verticalPull"),
    Pick("Pullups", "verticalPull", "Pull-Up"),
    Pick("Chin-Up", "verticalPull"),
    Pick("Straight-Arm Pulldown", "other"),
    Pick("Hyperextensions (Back Extensions)", "hipDominant", "Back Extension"),
    Pick("Band Assisted Pull-Up", "verticalPull"),
    Pick("One Arm Lat Pulldown", "verticalPull"),
    Pick("Full Range-Of-Motion Lat Pulldown", "verticalPull"),
    Pick("Rope Straight-Arm Pulldown", "verticalPull"),
    Pick("Kneeling High Pulley Row", "horizontalPull"),
    Pick("Kneeling Single-Arm High Pulley Row", "horizontalPull"),
    Pick("Elevated Cable Rows", "horizontalPull"),
    Pick("Leverage High Row", "horizontalPull"),
    Pick("Leverage Iso Row", "horizontalPull"),
    Pick("Suspended Row", "horizontalPull"),
    Pick("Inverted Row with Straps", "horizontalPull"),
    Pick("Scapular Pull-Up", "verticalPull"),
    # -- Shoulders --------------------------------------------------------
    Pick("Standing Military Press", "verticalPush", "Overhead Press"),
    Pick("Dumbbell Shoulder Press", "verticalPush", "Dumbbell Overhead Press"),
    Pick("Seated Dumbbell Press", "verticalPush"),
    Pick("Arnold Dumbbell Press", "verticalPush", "Arnold Press"),
    Pick("Machine Shoulder (Military) Press", "verticalPush"),
    Pick("Push Press", "verticalPush"),
    Pick("Handstand Push-Ups", "verticalPush"),
    Pick("Side Lateral Raise", "other", "Lateral Raise"),
    Pick("Seated Side Lateral Raise", "other"),
    Pick("Cable Seated Lateral Raise", "other", "Cable Lateral Raise"),
    Pick("Front Dumbbell Raise", "other"),
    Pick("Reverse Flyes", "other", "Rear Delt Fly (Bent-Over Dumbbell)"),
    Pick("Reverse Machine Flyes", "other", "Rear Delt Fly (Machine)"),
    Pick("Cable Rear Delt Fly", "other"),
    Pick("Face Pull", "other"),
    Pick("Upright Barbell Row", "verticalPull", "Upright Row"),
    Pick("Band Pull Apart", "other", "Band Pull-Apart"),
    Pick("Battling Ropes", "other", "Battle Rope Waves"),
    Pick("Kettlebell Turkish Get-Up (Squat style)", "other", "Turkish Get-Up"),
    Pick("Cable Shoulder Press", "verticalPush"),
    Pick("Seated Cable Shoulder Press", "verticalPush"),
    Pick("Standing Dumbbell Press", "verticalPush"),
    Pick("Standing Alternating Dumbbell Press", "verticalPush"),
    Pick("Kettlebell Arnold Press", "verticalPush"),
    Pick("Dumbbell One-Arm Shoulder Press", "verticalPush"),
    Pick("Lateral Raise - With Bands", "other"),
    Pick("Front Cable Raise", "other"),
    Pick("Dumbbell Scaption", "other"),
    Pick("External Rotation with Band", "other"),
    Pick("Cable Internal Rotation", "other"),
    Pick("Cuban Press", "verticalPush"),
    # -- Arms: biceps -----------------------------------------------------
    Pick("Barbell Curl", "other"),
    Pick("EZ-Bar Curl", "other"),
    Pick("Dumbbell Bicep Curl", "other", "Dumbbell Curl"),
    Pick("Incline Dumbbell Curl", "other"),
    Pick("Hammer Curls", "other", "Hammer Curl"),
    Pick("Cable Hammer Curls - Rope Attachment", "other"),
    Pick("Concentration Curls", "other", "Concentration Curl"),
    Pick("Preacher Curl", "other"),
    Pick("Standing Biceps Cable Curl", "other"),
    Pick("Reverse Barbell Curl", "other", "Reverse Curl"),
    Pick("Zottman Curl", "other"),
    Pick("Spider Curl", "other"),
    Pick("Alternate Hammer Curl", "other"),
    Pick("Cross Body Hammer Curl", "other"),
    Pick("Drag Curl", "other"),
    Pick("High Cable Curls", "other"),
    Pick("Cable Preacher Curl", "other"),
    Pick("Machine Bicep Curl", "other"),
    Pick("Preacher Hammer Dumbbell Curl", "other"),
    Pick("Seated Dumbbell Curl", "other"),
    Pick("Standing Concentration Curl", "other"),
    Pick("Two-Arm Dumbbell Preacher Curl", "other"),
    # -- Arms: triceps ----------------------------------------------------
    Pick("Triceps Pushdown - Rope Attachment", "other", "Tricep Pushdown"),
    Pick("Triceps Pushdown - V-Bar Attachment", "other"),
    Pick("Close-Grip Barbell Bench Press", "horizontalPush", "Close-Grip Bench Press"),
    Pick("EZ-Bar Skullcrusher", "other", "Skull Crusher"),
    Pick("Cable Rope Overhead Triceps Extension", "other", "Overhead Tricep Extension"),
    Pick("Seated Triceps Press", "other"),
    Pick("Tricep Dumbbell Kickback", "other"),
    Pick("Dips - Triceps Version", "other", "Tricep Dip"),
    Pick("Bench Dips", "other"),
    Pick("Machine Triceps Extension", "other"),
    Pick("Band Skull Crusher", "other"),
    Pick("Cable Incline Triceps Extension", "other"),
    Pick("Cable One Arm Tricep Extension", "other"),
    Pick("Dip Machine", "other"),
    Pick("JM Press", "horizontalPush"),
    Pick("Lying Dumbbell Tricep Extension", "other"),
    Pick("Reverse Grip Triceps Pushdown", "other"),
    Pick("Tate Press", "other"),
    # -- Legs -------------------------------------------------------------
    Pick("Barbell Squat", "kneeDominant", "Back Squat"),
    Pick("Front Barbell Squat", "kneeDominant", "Front Squat"),
    Pick("Goblet Squat", "kneeDominant"),
    Pick("Bodyweight Squat", "kneeDominant"),
    Pick("Box Squat", "kneeDominant"),
    Pick("Overhead Squat", "kneeDominant"),
    Pick("Zercher Squats", "kneeDominant"),
    Pick("Hack Squat", "kneeDominant"),
    Pick("Smith Machine Squat", "kneeDominant"),
    Pick("One Leg Barbell Squat", "kneeDominant"),
    Pick("Leg Press", "kneeDominant"),
    Pick("Leg Extensions", "kneeDominant", "Leg Extension"),
    Pick("Lying Leg Curls", "hipDominant", "Leg Curl"),
    Pick("Seated Leg Curl", "hipDominant"),
    Pick("Glute Ham Raise", "hipDominant"),
    Pick("Romanian Deadlift", "hipDominant"),
    Pick("Stiff-Legged Dumbbell Deadlift", "hipDominant", "Dumbbell Romanian Deadlift"),
    Pick("Stiff-Legged Barbell Deadlift", "hipDominant"),
    Pick("Good Morning", "hipDominant"),
    Pick("Barbell Lunge", "kneeDominant", "Lunge"),
    Pick("Dumbbell Lunges", "kneeDominant"),
    Pick("Barbell Walking Lunge", "kneeDominant"),
    Pick("Split Squat with Dumbbells", "kneeDominant"),
    # The upstream Smith-machine variant is the closest verified free image
    # set for a Bulgarian/rear-foot-elevated split squat.
    Pick("Smith Single-Leg Split Squat", "kneeDominant", "Bulgarian Split Squat"),
    Pick("Dumbbell Step Ups", "kneeDominant", "Step-Up"),
    Pick("Thigh Adductor", "other"),
    Pick("Barbell Full Squat", "kneeDominant"),
    Pick("Dumbbell Squat", "kneeDominant"),
    Pick("Plie Dumbbell Squat", "kneeDominant"),
    Pick("Narrow Stance Leg Press", "kneeDominant"),
    Pick("Wide Stance Barbell Squat", "kneeDominant"),
    Pick("Dumbbell Rear Lunge", "kneeDominant"),
    Pick("Bodyweight Walking Lunge", "kneeDominant"),
    Pick("Barbell Step Ups", "kneeDominant"),
    Pick("Elevated Back Lunge", "kneeDominant"),
    Pick("Single-Leg Leg Extension", "kneeDominant"),
    Pick("Standing Leg Curl", "hipDominant"),
    Pick("Ball Leg Curl", "hipDominant"),
    Pick("Floor Glute-Ham Raise", "hipDominant"),
    Pick("Natural Glute Ham Raise", "hipDominant"),
    Pick("Kettlebell One-Legged Deadlift", "hipDominant"),
    # -- Glutes -----------------------------------------------------------
    Pick("Barbell Hip Thrust", "hipDominant", "Hip Thrust"),
    Pick("Barbell Glute Bridge", "hipDominant", "Glute Bridge"),
    Pick("Single Leg Glute Bridge", "hipDominant"),
    Pick("Pull Through", "hipDominant", "Cable Pull-Through"),
    Pick("One-Legged Cable Kickback", "hipDominant"),
    Pick("Glute Kickback", "hipDominant"),
    Pick("Thigh Abductor", "other"),
    Pick("Step-up with Knee Raise", "kneeDominant"),
    Pick("Physioball Hip Bridge", "hipDominant"),
    Pick("Hip Extension with Bands", "hipDominant"),
    Pick("Hip Lift with Band", "hipDominant"),
    Pick("Monster Walk", "other"),
    Pick("Platform Hamstring Slides", "hipDominant"),
    # -- Core -------------------------------------------------------------
    Pick("Plank", "antiRotation"),
    Pick("Side Bridge", "antiRotation", "Side Plank"),
    Pick("Dead Bug", "antiRotation"),
    Pick("Pallof Press", "antiRotation"),
    Pick("Barbell Ab Rollout - On Knees", "antiRotation", "Ab Wheel Rollout"),
    Pick("Ab Roller", "antiRotation"),
    Pick("Crunches", "other"),
    Pick("Sit-Up", "other"),
    Pick("Decline Crunch", "other"),
    Pick("Reverse Crunch", "other"),
    Pick("Cable Crunch", "other"),
    Pick("Hanging Leg Raise", "other"),
    Pick("Russian Twist", "rotation"),
    Pick("Standing Cable Wood Chop", "rotation"),
    Pick("Mountain Climbers", "other"),
    Pick("3/4 Sit-Up", "other"),
    Pick("Ab Crunch Machine", "other"),
    Pick("Air Bike", "other"),
    Pick("Alternate Heel Touchers", "other"),
    Pick("Cross-Body Crunch", "rotation"),
    Pick("Exercise Ball Crunch", "other"),
    Pick("Flat Bench Lying Leg Raise", "other"),
    Pick("Hanging Pike", "other"),
    Pick("Jackknife Sit-Up", "other"),
    Pick("Landmine 180's", "rotation"),
    Pick("Pallof Press With Rotation", "rotation"),
    Pick("Stomach Vacuum", "other"),
    # -- Calves -----------------------------------------------------------
    Pick("Standing Calf Raises", "other", "Calf Raise"),
    Pick("Seated Calf Raise", "other"),
    Pick("Standing Barbell Calf Raise", "other", "Standing Calf Raise (Barbell)"),
    Pick("Calf Press On The Leg Press Machine", "other"),
    Pick("Donkey Calf Raises", "other"),
    Pick("Standing Dumbbell Calf Raise", "other"),
    # -- Traps ------------------------------------------------------------
    Pick("Barbell Shrug", "other", "Shrug"),
    Pick("Dumbbell Shrug", "other"),
    Pick("Cable Shrugs", "other"),
    Pick("Leverage Shrug", "other"),
    Pick("Upright Cable Row", "verticalPull"),
    # -- Forearms ---------------------------------------------------------
    Pick("Palms-Up Barbell Wrist Curl Over A Bench", "other", "Wrist Curl"),
    Pick("Palms-Down Wrist Curl Over A Bench", "other"),
    Pick("Wrist Roller", "other"),
    Pick("Farmer's Walk", "carry"),
    Pick("Plate Pinch", "carry"),
    # -- Neck -------------------------------------------------------------
    Pick("Lying Face Up Plate Neck Resistance", "other", "Neck Curl"),
    Pick("Lying Face Down Plate Neck Resistance", "other", "Neck Extension"),
    # -- Loaded carries / conditioning ------------------------------------
    Pick("Sled Push", "carry"),
    Pick("One-Arm Kettlebell Swings", "hipDominant"),
    Pick("Kettlebell Sumo High Pull", "hipDominant"),
    # -- Conditioning / mobility -----------------------------------------
    Pick("Bicycling, Stationary", "other"),
    Pick("Elliptical Trainer", "other"),
    Pick("Jogging, Treadmill", "other"),
    Pick("Recumbent Bike", "other"),
    Pick("Rope Jumping", "other"),
    Pick("Rowing, Stationary", "horizontalPull"),
    Pick("Stairmaster", "other"),
    Pick("Walking, Treadmill", "other"),
    Pick("Bench Jump", "kneeDominant"),
    Pick("Front Box Jump", "kneeDominant"),
    Pick("Knee Tuck Jump", "kneeDominant"),
    Pick("Lateral Bound", "kneeDominant"),
    Pick("World's Greatest Stretch", "other"),
    Pick("Inchworm", "other"),
    # -- Batch 3 (50 more, added 2026-08-26) -------------------------------
    # -- Chest --------------------------------------------------------------
    Pick("Wide-Grip Barbell Bench Press", "horizontalPush"),
    Pick("Smith Machine Decline Press", "horizontalPush"),
    Pick("One Arm Dumbbell Bench Press", "horizontalPush"),
    Pick("Push-Ups With Feet Elevated", "horizontalPush", "Feet-Elevated Push-Up"),
    # -- Back -----------------------------------------------------------------
    Pick("Weighted Pull Ups", "verticalPull", "Weighted Pull-Up"),
    Pick("Muscle Up", "verticalPull"),
    Pick("Incline Bench Pull", "horizontalPull"),
    Pick("Seated One-arm Cable Pulley Rows", "horizontalPull", "Seated One-Arm Cable Row"),
    Pick("Superman", "hipDominant"),
    Pick("Reverse Hyperextension", "hipDominant"),
    # -- Shoulders --------------------------------------------------------
    Pick("Seated Barbell Military Press", "verticalPush", "Seated Barbell Overhead Press"),
    Pick("Front Plate Raise", "other", "Plate Front Raise"),
    Pick("Cable Rope Rear-Delt Rows", "horizontalPull", "Cable Rear-Delt Row"),
    Pick("Dumbbell Lying Rear Lateral Raise", "other", "Lying Rear Delt Raise"),
    Pick("External Rotation", "other", "Shoulder External Rotation"),
    Pick("Barbell Rear Delt Row", "horizontalPull"),
    # -- Arms -----------------------------------------------------------------
    Pick("Close-Grip Standing Barbell Curl", "other"),
    Pick("Standing Dumbbell Reverse Curl", "other", "Standing Reverse Dumbbell Curl"),
    Pick("Dumbbell Alternate Bicep Curl", "other", "Alternating Standing Dumbbell Curl"),
    Pick("Incline Hammer Curls", "other", "Incline Hammer Curl"),
    Pick("Parallel Bar Dip", "other"),
    Pick("Weighted Bench Dip", "other"),
    Pick("Standing Overhead Barbell Triceps Extension", "other"),
    Pick("Kneeling Cable Triceps Extension", "other"),
    Pick("Wrist Circles", "other"),
    Pick("Seated Palms-Down Barbell Wrist Curl", "other", "Seated Barbell Wrist Curl"),
    # -- Legs / glutes ------------------------------------------------------
    Pick("Narrow Stance Squats", "kneeDominant", "Narrow Stance Squat"),
    Pick("Jefferson Squats", "kneeDominant", "Jefferson Squat"),
    Pick("Weighted Sissy Squat", "kneeDominant", "Sissy Squat"),
    Pick("Chair Squat", "kneeDominant"),
    Pick("Smith Machine Pistol Squat", "kneeDominant"),
    Pick("Standing Long Jump", "kneeDominant"),
    Pick("Romanian Deadlift from Deficit", "hipDominant", "Deficit Romanian Deadlift"),
    Pick("Seated Band Hamstring Curl", "hipDominant", "Band Seated Leg Curl"),
    Pick("Good Morning off Pins", "hipDominant"),
    Pick("Wide Stance Stiff Legs", "hipDominant", "Wide-Stance Stiff-Leg Deadlift"),
    Pick("Butt Lift (Bridge)", "hipDominant", "Bodyweight Glute Bridge"),
    Pick("Kneeling Squat", "kneeDominant"),
    Pick("Barbell Seated Calf Raise", "other", "Seated Barbell Calf Raise"),
    Pick("Calf Raise On A Dumbbell", "other", "Single-Leg Dumbbell Calf Raise"),
    # -- Core -----------------------------------------------------------------
    Pick("Barbell Ab Rollout", "antiRotation"),
    Pick("Cable Reverse Crunch", "other"),
    Pick("Weighted Crunches", "other", "Weighted Crunch"),
    Pick("Toe Touchers", "other", "Toe Touch"),
    Pick("Standing Cable Lift", "rotation"),
    Pick("Plate Twist", "rotation", "Weighted Plate Twist"),
    # -- Conditioning ------------------------------------------------------
    Pick("Box Jump (Multiple Response)", "kneeDominant", "Box Jump"),
    Pick("Yoke Walk", "carry"),
    Pick("Tire Flip", "hipDominant"),
    Pick("Rope Climb", "verticalPull"),
]


def slugify(name: str) -> str:
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -_/":
            out.append("-")
        # Everything else (apostrophes, parens, commas) is dropped rather
        # than turned into a separator, so "Farmer's Walk" is farmers-walk.
    slug = "".join(out)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-")


def source_id(upstream: dict) -> str:
    """Upstream's own id — already filename-safe, and unique across the dump."""
    return upstream["id"]


def fetch(url: str, dest: Path) -> Path:
    """Download to `dest` unless already cached."""
    if dest.exists():
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as response:
        dest.write_bytes(response.read())
    return dest


def load_upstream() -> dict[str, dict]:
    path = fetch(FEDB_JSON_URL, CACHE / "exercises.json")
    return {x["name"]: x for x in json.loads(path.read_text())}


def previous_seed() -> dict:
    return json.loads(SEED.read_text()) if SEED.exists() else {"exercises": []}


def build_media(pick: Pick, upstream: dict, dry_run: bool) -> list[dict]:
    """Download, recompress, and describe this exercise's images."""
    media: list[dict] = []
    for order, remote in enumerate(upstream.get("images", [])):
        cached = fetch(FEDB_IMAGE_URL + remote, CACHE / "images" / remote)
        # Flattened to a single directory on purpose. Flutter's `assets:`
        # entries are not recursive, so upstream's one-folder-per-exercise
        # layout would need all 251 directories listed in pubspec.yaml —
        # a list that silently rots the first time this script is re-run
        # with a different curation. Upstream ids are unique, so
        # "<id>_<n>.jpg" is collision-free and one entry covers the lot.
        relative = (
            f"assets/images/exercises/free_exercise_db/"
            f"{source_id(upstream)}_{order}.jpg"
        )
        if not dry_run:
            out = REPO / relative
            out.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(cached) as image:
                image = image.convert("RGB")
                if image.width > IMAGE_WIDTH:
                    height = round(image.height * IMAGE_WIDTH / image.width)
                    image = image.resize((IMAGE_WIDTH, height), Image.LANCZOS)
                image.save(out, "JPEG", quality=IMAGE_QUALITY, optimize=True)
        media.append(
            {
                "type": "image",
                "localAsset": relative,
                "sortOrder": order,
                "license": LICENSE,
                "attribution": ATTRIBUTION,
                "source": FEDB_HOME,
            }
        )
    return media


def build(dry_run: bool) -> tuple[dict, list[str]]:
    upstream_by_name = load_upstream()
    old = previous_seed()

    # Display name -> previous id, so a rebuilt entry lands on the row a
    # user's workout history already points at.
    old_ids = {e["name"]: e["id"] for e in old["exercises"]}
    # ...and the YouTube links worth carrying across, keyed the same way.
    old_videos = {
        e["name"]: [m for m in e.get("media", []) if m.get("type") == "video"]
        for e in old["exercises"]
    }

    missing = [p.upstream for p in CURATION if p.upstream not in upstream_by_name]
    if missing:
        raise SystemExit(
            "free-exercise-db no longer has these curated entries — the "
            "upstream dump renamed or dropped them, so the curation list "
            "needs updating:\n  " + "\n  ".join(missing)
        )

    seen_upstream: dict[str, str] = {}
    seen_display: dict[str, str] = {}
    for pick in CURATION:
        if pick.upstream in seen_upstream:
            raise SystemExit(
                f"{pick.upstream!r} is curated twice "
                f"(as {seen_upstream[pick.upstream]!r} and {pick.display!r})"
            )
        if pick.display in seen_display:
            raise SystemExit(
                f"display name {pick.display!r} is used twice — `name` is "
                "UNIQUE in the database, so this would fail at seed time"
            )
        seen_upstream[pick.upstream] = pick.display
        seen_display[pick.display] = pick.upstream

    # Ids for genuinely new exercises continue the ex_NNN sequence past
    # whatever the previous seed used, so a preserved id is never reissued.
    highest = 0
    for exercise in old["exercises"]:
        if exercise["id"].startswith("ex_"):
            try:
                highest = max(highest, int(exercise["id"][3:]))
            except ValueError:
                pass
    next_id = highest + 1

    exercises: list[dict] = []
    notes: list[str] = []
    for pick in CURATION:
        source = upstream_by_name[pick.upstream]
        display = pick.display

        if display in old_ids:
            exercise_id = old_ids[display]
        else:
            exercise_id = f"ex_{next_id:03d}"
            next_id += 1

        primary = [MUSCLES[m] for m in source.get("primaryMuscles", []) if m in MUSCLES]
        secondary = [
            MUSCLES[m] for m in source.get("secondaryMuscles", []) if m in MUSCLES
        ]
        muscles = []
        for muscle_id in dict.fromkeys(primary):
            muscles.append({"muscleId": muscle_id, "role": "primary"})
        for muscle_id in dict.fromkeys(secondary):
            if muscle_id not in primary:
                muscles.append({"muscleId": muscle_id, "role": "secondary"})
        if not muscles:
            notes.append(f"{display}: upstream lists no muscles")

        equipment_id = EQUIPMENT[source.get("equipment")]
        lowered = pick.upstream.lower()

        # The upstream name is kept as an alias whenever we rename, so
        # searching the library for "Pushups" still finds "Push-Up".
        aliases = [pick.upstream] if pick.name else []

        media = build_media(pick, source, dry_run)
        media.extend(old_videos.get(display, []))
        for order, entry in enumerate(media):
            entry["sortOrder"] = order

        exercises.append(
            {
                "id": exercise_id,
                "slug": slugify(display),
                "name": display,
                "description": "",
                "category": CATEGORIES[source["category"]],
                "difficulty": LEVELS[source["level"]],
                "movementPattern": pick.pattern,
                "forceType": FORCES[source.get("force")],
                "mechanic": MECHANICS[source.get("mechanic")],
                "isUnilateral": any(h in lowered for h in UNILATERAL_HINTS),
                "isBodyweight": equipment_id == "bodyweight",
                "muscles": muscles,
                "equipment": [{"equipmentId": equipment_id, "isRequired": True}],
                "instructions": source.get("instructions", []),
                "aliases": aliases,
                "media": media,
                "tags": [],
                "sources": [
                    {
                        "sourceName": "free-exercise-db",
                        "sourceUrl": FEDB_HOME,
                        "sourceExerciseId": source["id"],
                        "license": LICENSE,
                        "attribution": ATTRIBUTION,
                        "usedFor": "text+image",
                    }
                ],
            }
        )

    slugs = [e["slug"] for e in exercises]
    duplicate_slugs = {s for s in slugs if slugs.count(s) > 1}
    if duplicate_slugs:
        raise SystemExit(f"slug collision (slug is UNIQUE): {sorted(duplicate_slugs)}")

    seed = {
        "seedVersion": old.get("seedVersion", 0) + 1,
        "muscles": old["muscles"],
        "equipment": old["equipment"],
        "exercises": exercises,
    }
    return seed, notes


def purge_unlicensed(dry_run: bool) -> list[Path]:
    """Delete every image that did not come from free-exercise-db."""
    doomed = [
        path
        for path in sorted(IMAGE_ROOT.rglob("*"))
        if path.is_file() and FEDB_IMAGES not in path.parents
    ]
    if not dry_run:
        for path in doomed:
            path.unlink()
    return doomed


def prune_orphan_images(seed: dict, dry_run: bool) -> list[Path]:
    """Delete free-exercise-db images no curated exercise references."""
    referenced = {
        REPO / m["localAsset"]
        for e in seed["exercises"]
        for m in e["media"]
        if "localAsset" in m
    }
    doomed = [
        path
        for path in sorted(FEDB_IMAGES.rglob("*"))
        if path.is_file() and path not in referenced
    ]
    if not dry_run:
        for path in doomed:
            path.unlink()
        for directory in sorted(FEDB_IMAGES.rglob("*"), reverse=True):
            if directory.is_dir() and not any(directory.iterdir()):
                directory.rmdir()
    return doomed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would change without writing anything",
    )
    args = parser.parse_args()

    old = previous_seed()
    seed, notes = build(args.dry_run)

    old_names = {e["name"] for e in old["exercises"]}
    new_names = {e["name"] for e in seed["exercises"]}
    preserved = sum(
        1
        for e in seed["exercises"]
        if e["id"] in {o["id"] for o in old["exercises"]}
    )

    purged = purge_unlicensed(args.dry_run)
    if not args.dry_run:
        SEED.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n")
    orphans = prune_orphan_images(seed, args.dry_run)

    print(f"seedVersion      {old.get('seedVersion')} -> {seed['seedVersion']}")
    print(f"exercises        {len(old['exercises'])} -> {len(seed['exercises'])}")
    print(f"ids preserved    {preserved}")
    print(f"dropped          {len(old_names - new_names)}")
    print(f"added            {len(new_names - old_names)}")
    print(f"images purged    {len(purged)} unlicensed, {len(orphans)} orphaned")
    if notes:
        print("\nnotes:")
        for note in notes:
            print(f"  {note}")
    if args.dry_run:
        print("\n(dry run — nothing written)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
