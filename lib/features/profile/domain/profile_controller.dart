import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/profiles.dart';

part 'profile_controller.g.dart';

const _uuid = Uuid();

/// The Personal Details form's working copy.
///
/// Held in memory until Confirm, like `ProgramEditorController`'s draft: a
/// half-filled form isn't worth resuming, and writing on every keystroke
/// would spray body-metric rows into the Progress charts.
class ProfileDraft {
  const ProfileDraft({
    this.displayName = '',
    this.dateOfBirth,
    this.sex,
    this.heightCm,
    this.weightKg,
  });

  final String displayName;
  final DateTime? dateOfBirth;
  final String? sex;
  final double? heightCm;

  /// Not a profile column — this is today's `body_metrics_table` entry,
  /// loaded and saved through `BodyMetricsDao` so the Progress charts stay
  /// the single source of truth for bodyweight.
  final double? weightKg;

  ProfileDraft copyWith({
    String? displayName,
    DateTime? Function()? dateOfBirth,
    String? Function()? sex,
    double? Function()? heightCm,
    double? Function()? weightKg,
  }) {
    return ProfileDraft(
      displayName: displayName ?? this.displayName,
      dateOfBirth: dateOfBirth == null ? this.dateOfBirth : dateOfBirth(),
      sex: sex == null ? this.sex : sex(),
      heightCm: heightCm == null ? this.heightCm : heightCm(),
      weightKg: weightKg == null ? this.weightKg : weightKg(),
    );
  }
}

/// Loads the stored profile plus the latest known bodyweight, tracks edits,
/// and writes both back on [save].
@riverpod
class ProfileController extends _$ProfileController {
  @override
  Future<ProfileDraft> build() async {
    final Profile? profile = await ref.watch(profileDaoProvider).get();
    // Seeded from the most recent measurement rather than left blank: the
    // user has usually logged a weight long before they open this screen.
    final latest = await ref.watch(bodyMetricsDaoProvider).getLatest();

    return ProfileDraft(
      displayName: profile?.displayName ?? '',
      dateOfBirth: profile?.dateOfBirth,
      sex: profile?.sex,
      heightCm: profile?.heightCm,
      weightKg: latest?.weightKg,
    );
  }

  void setDisplayName(String value) =>
      _update((d) => d.copyWith(displayName: value));

  void setDateOfBirth(DateTime? value) => _update(
        (d) => d.copyWith(
          dateOfBirth: () =>
              value == null ? null : DateTime.utc(value.year, value.month, value.day),
        ),
      );

  void setSex(String? value) => _update((d) => d.copyWith(sex: () => value));

  void setHeightCm(double? value) =>
      _update((d) => d.copyWith(heightCm: () => value));

  void setWeightKg(double? value) =>
      _update((d) => d.copyWith(weightKg: () => value));

  /// Persists the profile, and the weight as today's body-metrics entry.
  Future<void> save() async {
    final ProfileDraft? draft = state.value;
    if (draft == null) throw StateError('Profile draft is not loaded yet.');

    final String name = draft.displayName.trim();
    await ref.read(profileDaoProvider).upsert(
          ProfilesTableCompanion(
            displayName: Value(name.isEmpty ? null : name),
            dateOfBirth: Value(draft.dateOfBirth),
            sex: Value(draft.sex),
            heightCm: Value(draft.heightCm),
          ),
        );

    final double? weightKg = draft.weightKg;
    if (weightKg != null && weightKg > 0) {
      final DateTime today = DateTime.now().toUtc();
      // `upsert` normalizes to UTC midnight and replaces any entry already
      // logged today, so confirming twice doesn't create a duplicate.
      await ref.read(bodyMetricsDaoProvider).upsert(
            BodyMetricsTableCompanion.insert(
              id: _uuid.v4(),
              date: today,
              weightKg: weightKg,
            ),
          );
    }
  }

  void _update(ProfileDraft Function(ProfileDraft) fn) {
    final ProfileDraft? draft = state.value;
    if (draft == null) return;
    state = AsyncData(fn(draft));
  }
}
