import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/profile_dao.dart';
import 'package:fittrack/core/database/tables/profiles.dart';
import 'package:fittrack/core/services/data_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late ProfileDao dao;

  setUp(() {
    database = AppDatabase.forTesting();
    dao = ProfileDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('reads back null before anything has been saved', () async {
    expect(await dao.get(), isNull);
  });

  test('the first upsert creates the row and stamps both timestamps',
      () async {
    await dao.upsert(
      const ProfilesTableCompanion(
        displayName: Value('Mustafa Salih'),
        heightCm: Value(172),
      ),
    );

    final profile = await dao.get();
    expect(profile, isNotNull);
    expect(profile!.id, Profile.singletonId);
    expect(profile.displayName, 'Mustafa Salih');
    expect(profile.heightCm, 172);
    expect(profile.createdAt, isNotNull);
    expect(profile.updatedAt, isNotNull);
  });

  test('a later upsert leaves fields it does not mention alone', () async {
    await dao.upsert(
      ProfilesTableCompanion(
        displayName: const Value('Mustafa Salih'),
        heightCm: const Value(172),
        dateOfBirth: Value(DateTime.utc(1990, 8, 7)),
      ),
    );

    // The sign-in hook writes only the account columns.
    await dao.linkAccount(userId: 'user-1', email: 'a@b.co');

    final profile = await dao.get();
    expect(profile!.remoteUserId, 'user-1');
    expect(profile.email, 'a@b.co');
    // Everything the user typed as a guest must survive signing in.
    expect(profile.displayName, 'Mustafa Salih');
    expect(profile.heightCm, 172);
    expect(profile.dateOfBirth, DateTime.utc(1990, 8, 7));
  });

  test('there is only ever one profile row, however many upserts run',
      () async {
    await dao.upsert(const ProfilesTableCompanion(displayName: Value('A')));
    await dao.upsert(const ProfilesTableCompanion(displayName: Value('B')));
    await dao.linkAccount(userId: 'user-1', email: 'a@b.co');

    final rows = await database.select(database.profilesTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.displayName, 'B');
  });

  test('linkAccount on a fresh install creates the row rather than failing',
      () async {
    await dao.linkAccount(userId: 'user-1', email: 'a@b.co');

    final profile = await dao.get();
    expect(profile!.remoteUserId, 'user-1');
    expect(profile.isLinkedToAccount, isTrue);
  });

  test('unlinkAccount clears the account but keeps the personal details',
      () async {
    await dao.upsert(const ProfilesTableCompanion(displayName: Value('Mus')));
    await dao.linkAccount(userId: 'user-1', email: 'a@b.co');

    await dao.unlinkAccount();

    final profile = await dao.get();
    expect(profile!.remoteUserId, isNull);
    expect(profile.email, isNull);
    // Signing out is not deleting: the data is local and still theirs.
    expect(profile.displayName, 'Mus');
    expect(profile.isLinkedToAccount, isFalse);
  });

  test('watch emits the current profile and then each change', () async {
    final emissions = <String?>[];
    final sub = dao.watch().listen((p) => emissions.add(p?.displayName));
    // Let the initial (empty) emission land before writing, otherwise the
    // first write races it and the stream opens straight onto 'A'.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await dao.upsert(const ProfilesTableCompanion(displayName: Value('A')));
    await dao.upsert(const ProfilesTableCompanion(displayName: Value('B')));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(emissions.first, isNull);
    expect(emissions.last, 'B');
  });

  test('a date of birth survives the round trip as the same calendar date',
      () async {
    // Regression guard: Drift rebuilds epoch columns in the device's local
    // zone. West of UTC that turns UTC midnight into the previous day, so
    // this would have shown a birth date one day early for a large share of
    // users. `Profile.fromDrift` converts back with `toUtc()`.
    final DateTime dob = DateTime.utc(1990, 8, 7);
    await dao.upsert(ProfilesTableCompanion(dateOfBirth: Value(dob)));

    final stored = (await dao.get())!.dateOfBirth!;
    expect(stored.isUtc, isTrue);
    expect(stored, dob);
    expect(
      '${stored.year}-${stored.month}-${stored.day}',
      '1990-8-7',
    );
  });

  group('ageAt', () {
    test('counts whole years, not yet counting an upcoming birthday', () {
      final profile = Profile(
        id: Profile.singletonId,
        dateOfBirth: DateTime.utc(1990, 8, 7),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      expect(profile.ageAt(DateTime.utc(2026, 8, 7)), 36); // birthday itself
      expect(profile.ageAt(DateTime.utc(2026, 8, 6)), 35); // day before
      expect(profile.ageAt(DateTime.utc(2026, 9, 1)), 36);
      expect(profile.ageAt(DateTime.utc(2026, 1, 1)), 35); // earlier month
    });

    test('is null without a date of birth', () {
      final profile = Profile(
        id: Profile.singletonId,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(profile.ageAt(DateTime.utc(2026)), isNull);
    });
  });

  test('deleteAllUserData removes the profile, name and account link too',
      () async {
    await dao.upsert(const ProfilesTableCompanion(displayName: Value('Mus')));
    await dao.linkAccount(userId: 'user-1', email: 'a@b.co');

    await const DataExportService().deleteAllUserData(database);

    // Otherwise "delete all my data" leaves the next person looking at
    // someone else's name and email.
    expect(await dao.get(), isNull);
  });
}
