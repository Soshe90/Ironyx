import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/profile_dao.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The v6 -> v7 migration adds `profiles_table` for accounts and personal
/// details (ADR-8).
///
/// It is purely additive, and that is exactly what needs proving: an
/// existing install carrying real workout history must gain the new table
/// without losing a row, because the alternative — a failed migration on
/// launch — presents to the user as their entire training log vanishing.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ironyx_profiles_mig');
    dbFile = File('${tempDir.path}/test.sqlite');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// Writes the handful of v6 tables this test touches, then stamps the
  /// file as v6 so the real `onUpgrade` runs against it.
  void seedV6Database() {
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw
      ..execute('''
        CREATE TABLE workouts_table (
          id TEXT NOT NULL PRIMARY KEY,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          notes TEXT,
          total_volume_kg REAL NOT NULL DEFAULT 0,
          perceived_exertion INTEGER
        )
      ''')
      ..execute('''
        CREATE TABLE body_metrics_table (
          id TEXT NOT NULL PRIMARY KEY,
          date INTEGER NOT NULL,
          weight_kg REAL NOT NULL,
          body_fat_percentage REAL,
          lean_mass_kg REAL,
          waist_cm REAL,
          note TEXT,
          UNIQUE (date)
        )
      ''')
      // The v6 -> v7 migration this test targets doesn't touch
      // exercises_table, but the v7 -> v8 step (isCustom column) runs
      // right after it in the same onUpgrade chain and needs the table to
      // exist — matching its real v3+ shape closely enough for that.
      ..execute('''
        CREATE TABLE exercises_table (
          id TEXT NOT NULL PRIMARY KEY,
          slug TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL UNIQUE,
          description TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL,
          difficulty TEXT NOT NULL,
          movement_pattern TEXT NOT NULL,
          force_type TEXT,
          mechanic TEXT,
          is_unilateral INTEGER NOT NULL DEFAULT 0,
          is_bodyweight INTEGER NOT NULL DEFAULT 0,
          seed_version INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute(
        'INSERT INTO workouts_table (id, started_at, ended_at, '
        "total_volume_kg) VALUES ('w1', 1750000000, 1750003600, 4200.5)",
      )
      ..execute(
        'INSERT INTO body_metrics_table (id, date, weight_kg) '
        "VALUES ('b1', 1750000000, 94.0)",
      )
      ..execute('PRAGMA user_version = 6')
      ..close();
  }

  test('upgrading a v6 database adds profiles_table and keeps existing data',
      () async {
    seedV6Database();

    final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(db.close);

    // Opening is what triggers the migration.
    final profile = await ProfileDao(db).get();
    expect(profile, isNull, reason: 'a fresh table starts empty');

    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle()
        .then((r) => r.data.values.first);
    expect(version, db.schemaVersion);

    // The pre-existing rows must be untouched.
    final workout = await db
        .customSelect(
            "SELECT total_volume_kg FROM workouts_table WHERE id = 'w1'")
        .getSingle();
    expect(workout.data['total_volume_kg'], 4200.5);

    final metric = await db
        .customSelect(
            "SELECT weight_kg FROM body_metrics_table WHERE id = 'b1'")
        .getSingle();
    expect(metric.data['weight_kg'], 94.0);
  });

  test('the upgraded table accepts writes, and survives a reopen', () async {
    seedV6Database();

    final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
    await ProfileDao(db).upsert(
      const ProfilesTableCompanion(
        displayName: Value('Mustafa Salih'),
        heightCm: Value(172),
      ),
    );
    await db.close();

    // Reopening at the current version must not re-run the migration and
    // wipe what was just written.
    final reopened = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(reopened.close);

    final profile = await ProfileDao(reopened).get();
    expect(profile!.displayName, 'Mustafa Salih');
    expect(profile.heightCm, 172);
  });
}
