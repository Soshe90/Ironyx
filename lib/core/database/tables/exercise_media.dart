import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'exercises.dart';

part 'exercise_media.freezed.dart';

/// A picture, gif, video link, or thumbnail attached to an exercise.
///
/// Replaces the old single nullable `imageUrl`/`videoUrl` columns. The
/// picture-resolution fallback chain (curated image → thumbnail derived
/// from a video link → equipment icon) now walks this list by [sortOrder]
/// instead of checking two columns.
class ExerciseMediaTable extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  /// image / gif / video / thumbnail.
  TextColumn get type => text()();

  /// Remote URL. Exactly one of [url] / [localAsset] is expected to be set.
  TextColumn get url => text().nullable()();

  /// Bundled asset path, for media shipped with the app instead of fetched.
  TextColumn get localAsset => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  TextColumn get license => text().nullable()();
  TextColumn get attribution => text().nullable()();
  TextColumn get source => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

enum ExerciseMediaType { image, gif, video, thumbnail }

/// Freezed model for a media row.
@freezed
abstract class ExerciseMedia with _$ExerciseMedia {
  const factory ExerciseMedia({
    required String id,
    required String exerciseId,
    required ExerciseMediaType type,
    String? url,
    String? localAsset,
    required int sortOrder,
    String? license,
    String? attribution,
    String? source,
  }) = _ExerciseMedia;

  factory ExerciseMedia.fromDrift(ExerciseMediaTableData row) => ExerciseMedia(
        id: row.id,
        exerciseId: row.exerciseId,
        type: ExerciseMediaType.values.byName(row.type),
        url: row.url,
        localAsset: row.localAsset,
        sortOrder: row.sortOrder,
        license: row.license,
        attribution: row.attribution,
        source: row.source,
      );
}
