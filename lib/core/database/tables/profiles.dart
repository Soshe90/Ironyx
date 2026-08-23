import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

part 'profiles.freezed.dart';

/// Profiles table — who the trainee is, as opposed to what they lifted.
///
/// Exactly one row, keyed by [Profile.singletonId]: this is a personal
/// tracker, one install per person. Signing in associates that single row
/// with an account via [remoteUserId] rather than creating a second profile,
/// because the local history already belongs to whoever is holding the
/// phone.
///
/// **Body weight is deliberately absent.** `body_metrics_table` already owns
/// weight-by-date and the Progress charts read from it; a second copy here
/// would immediately disagree with itself. The Personal Details screen
/// writes weight through `BodyMetricsDao.upsert`.
class ProfilesTable extends Table {
  /// Always [Profile.singletonId].
  TextColumn get id => text()();

  /// The auth backend's user id once signed in, null while a guest.
  ///
  /// Nullable rather than a foreign key: accounts live on a server, guests
  /// are first-class, and the local database must stand alone.
  TextColumn get remoteUserId => text().nullable()();

  /// Email of the associated account, cached so the Settings screen can
  /// show it without a network call. Null while a guest.
  TextColumn get email => text().nullable()();

  /// Display name, as entered on the Personal Details screen.
  TextColumn get displayName => text().nullable()();

  /// Date of birth, UTC midnight. Date only — the time component is never
  /// meaningful here.
  DateTimeColumn get dateOfBirth => dateTime().nullable()();

  /// A loose, display-only label, following `ProgramsTable.splitType`'s
  /// precedent rather than an enum. The app must not hard-code the set of
  /// answers a person can give to this.
  TextColumn get sex => text().nullable()();

  /// Height in centimetres (ADR-1: metric is the storage unit; display
  /// conversion is a presentation concern).
  RealColumn get heightCm => real().nullable()();

  /// Desired number of completed sessions per Monday-Sunday week.
  /// Null means the user has not configured a target; the domain layer uses 3.
  IntColumn get weeklySessionTarget => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for the profile row.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    String? remoteUserId,
    String? email,
    String? displayName,
    DateTime? dateOfBirth,
    String? sex,
    double? heightCm,
    int? weeklySessionTarget,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Profile;

  const Profile._();

  /// The one and only profile row's primary key.
  static const String singletonId = 'local_profile';

  /// Every [DateTime] is converted back to UTC on the way out.
  ///
  /// Drift stores these columns as an epoch int and rebuilds them in the
  /// device's *local* zone, so a value written as `DateTime.utc(1990, 8, 7)`
  /// comes back as a local time on either side of that midnight. For
  /// [dateOfBirth] that isn't cosmetic: anywhere west of UTC, local
  /// reconstruction of UTC midnight lands on the previous day and the
  /// screen would show a birth date one day early. `toUtc()` is exact —
  /// same instant, original calendar date.
  factory Profile.fromDrift(ProfilesTableData row) => Profile(
        id: row.id,
        remoteUserId: row.remoteUserId,
        email: row.email,
        displayName: row.displayName,
        dateOfBirth: row.dateOfBirth?.toUtc(),
        sex: row.sex,
        heightCm: row.heightCm,
        weeklySessionTarget: row.weeklySessionTarget,
        createdAt: row.createdAt.toUtc(),
        updatedAt: row.updatedAt.toUtc(),
      );

  /// Whether this profile is linked to an account.
  bool get isLinkedToAccount => remoteUserId != null;

  /// Age in whole years at [now], or null if no date of birth is set.
  int? ageAt(DateTime now) {
    final DateTime? birth = dateOfBirth;
    if (birth == null) return null;
    var age = now.year - birth.year;
    // Not yet had this year's birthday.
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }
}
