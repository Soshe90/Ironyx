import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/profiles.dart';

part 'profile_dao.g.dart';

/// Reads and writes the single local profile row.
///
/// Every method targets [Profile.singletonId]; callers never supply an id,
/// which is what keeps "one install, one person" true by construction rather
/// than by convention.
@DriftAccessor(tables: [ProfilesTable])
class ProfileDao extends DatabaseAccessor<AppDatabase> with _$ProfileDaoMixin {
  ProfileDao(super.db);

  /// The profile, or null before anything has ever been saved.
  Future<Profile?> get() =>
      (select(profilesTable)..where((t) => t.id.equals(Profile.singletonId)))
          .getSingleOrNull()
          .then((row) => row == null ? null : Profile.fromDrift(row));

  /// Watches the profile so the Settings and Personal Details screens
  /// refresh themselves after a save, rather than needing invalidation.
  Stream<Profile?> watch() =>
      (select(profilesTable)..where((t) => t.id.equals(Profile.singletonId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : Profile.fromDrift(row));

  /// Applies [changes] to the profile, creating the row on first write.
  ///
  /// Absent fields in [changes] are left untouched, so the Personal Details
  /// form and the sign-in hook can each write only what they own without
  /// clobbering the other's values.
  Future<void> upsert(ProfilesTableCompanion changes) {
    return transaction(() async {
      final DateTime now = DateTime.now().toUtc();
      final existing = await (select(profilesTable)
            ..where((t) => t.id.equals(Profile.singletonId)))
          .getSingleOrNull();

      if (existing == null) {
        await into(profilesTable).insert(
          changes.copyWith(
            id: const Value(Profile.singletonId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return;
      }

      await (update(profilesTable)
            ..where((t) => t.id.equals(Profile.singletonId)))
          .write(changes.copyWith(updatedAt: Value(now)));
    });
  }

  /// Associates the local profile with a signed-in account.
  ///
  /// Only touches the account columns — a returning user keeps the name,
  /// date of birth, sex and height they already entered as a guest.
  Future<void> linkAccount({required String userId, required String email}) =>
      upsert(
        ProfilesTableCompanion(
          remoteUserId: Value(userId),
          email: Value(email),
        ),
      );

  /// Clears the account association on sign-out, leaving the personal
  /// details in place: the data is local and still the user's.
  Future<void> unlinkAccount() => upsert(
        const ProfilesTableCompanion(
          remoteUserId: Value(null),
          email: Value(null),
        ),
      );
}
