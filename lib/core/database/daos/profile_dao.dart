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

  /// Stores the weekly completed-session target used by Progress adherence.
  Future<void> setWeeklySessionTarget(int? target) {
    if (target != null && (target < 1 || target > 7)) {
      throw ArgumentError.value(target, 'target', 'must be between 1 and 7');
    }
    return upsert(
      ProfilesTableCompanion(weeklySessionTarget: Value(target)),
    );
  }

  /// Whether linking [incomingUserId] would silently reassign this device's
  /// local training data away from a *different* account it is already
  /// linked to.
  ///
  /// False for a guest profile (never linked), for no profile at all, and
  /// for a profile already linked to the same account — all ordinary,
  /// harmless links. True only when a real account switch is about to
  /// happen on a device that still holds another account's data: the
  /// history, body metrics and personal details are local and belong to
  /// whoever was signed in before, and [linkAccount] alone does not clear
  /// any of that. Callers that get true back must resolve the conflict
  /// (typically: offer to erase local data first) before calling
  /// [linkAccount].
  Future<bool> hasConflictingAccount(String incomingUserId) async {
    final Profile? profile = await get();
    return profile != null &&
        profile.remoteUserId != null &&
        profile.remoteUserId != incomingUserId;
  }

  /// Associates the local profile with a signed-in account.
  ///
  /// Only touches the account columns — a returning user keeps the name,
  /// date of birth, sex and height they already entered as a guest.
  ///
  /// Callers reachable from a screen the user is actively looking at must
  /// check [hasConflictingAccount] first — this method itself has no way to
  /// ask "is that okay?", so it will happily reassign a device's data out
  /// from under the account that owned it.
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
