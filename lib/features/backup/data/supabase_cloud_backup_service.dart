import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/cloud_backup_service.dart';

/// Supabase-backed implementation of [CloudBackupService].
///
/// The second file permitted to reference `supabase_flutter` (ADR-8's
/// binding rule names both). Its job is the same as
/// `SupabaseAuthService`'s: translate the SDK's surface into the app's own
/// types so nothing downstream knows which backend is behind the seam.
///
/// One row per user in `public.backups`, guarded by row-level security so a
/// user can only ever read or write their own. See
/// `docs/cloud_backup_setup.sql`.
class SupabaseCloudBackupService implements CloudBackupService {
  SupabaseCloudBackupService(this._client);

  final sb.SupabaseClient _client;

  static const String _table = 'backups';
  static const Duration _operationTimeout = Duration(seconds: 45);

  @override
  bool get isAvailable => true;

  String get _userId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const CloudBackupFailure(CloudBackupFailureKind.notSignedIn);
    }
    return id;
  }

  @override
  Future<CloudBackupInfo?> head() => _guard(() async {
        final Map<String, dynamic>? row = await _client
            .from(_table)
            .select('updated_at, size_bytes, app_version, db_schema_version')
            .eq('user_id', _userId)
            .maybeSingle()
            .timeout(_operationTimeout);
        return row == null ? null : _toInfo(row);
      });

  @override
  Future<CloudBackupInfo> upload({
    required String payload,
    required String appVersion,
    required int dbSchemaVersion,
  }) =>
      _guard(() async {
        // Compressed before it leaves the device. A year of hard training
        // exports to ~1.4MB of JSON but gzips to ~40KB, because the
        // envelope repeats the same keys on every one of several thousand
        // rows. That is the difference between a backup a tester will run
        // on mobile data and one they won't.
        final String encoded = base64Encode(gzip.encode(utf8.encode(payload)));
        final Map<String, dynamic> row = await _client
            .from(_table)
            .upsert(<String, dynamic>{
              'user_id': _userId,
              'payload': encoded,
              'size_bytes': encoded.length,
              'app_version': appVersion,
              'db_schema_version': dbSchemaVersion,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select('updated_at, size_bytes, app_version, db_schema_version')
            .single()
            .timeout(_operationTimeout);
        return _toInfo(row);
      });

  @override
  Future<String> download() => _guard(() async {
        final Map<String, dynamic>? row = await _client
            .from(_table)
            .select('payload')
            .eq('user_id', _userId)
            .maybeSingle()
            .timeout(_operationTimeout);
        if (row == null) {
          throw const CloudBackupFailure(CloudBackupFailureKind.noBackupYet);
        }
        final String? encoded = row['payload'] as String?;
        if (encoded == null || encoded.isEmpty) {
          throw const CloudBackupFailure(CloudBackupFailureKind.noBackupYet);
        }
        try {
          return utf8.decode(gzip.decode(base64Decode(encoded)));
        } on Object catch (error) {
          throw CloudBackupFailure(
            CloudBackupFailureKind.corrupt,
            detail: '$error',
          );
        }
      });

  CloudBackupInfo _toInfo(Map<String, dynamic> row) => CloudBackupInfo(
        updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        sizeBytes: (row['size_bytes'] as num?)?.toInt() ?? 0,
        appVersion: row['app_version'] as String? ?? 'unknown',
        dbSchemaVersion: (row['db_schema_version'] as num?)?.toInt() ?? 0,
      );

  /// Translates every vendor and transport error into [CloudBackupFailure].
  /// An unmapped exception reaching the UI is a bug, same rule as ADR-8
  /// already applies to auth.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CloudBackupFailure {
      rethrow;
    } on sb.PostgrestException catch (error) {
      throw CloudBackupFailure(_kindOf(error), detail: error.message);
    } on sb.AuthException catch (error) {
      throw CloudBackupFailure(
        CloudBackupFailureKind.notSignedIn,
        detail: error.message,
      );
    } on TimeoutException catch (error) {
      throw CloudBackupFailure(
        CloudBackupFailureKind.offline,
        detail: '$error',
      );
    } on Object catch (error) {
      // Socket and DNS failures arrive as plain exceptions through the
      // Postgrest HTTP client rather than as a typed error.
      final String text = error.toString().toLowerCase();
      final bool looksOffline = text.contains('socket') ||
          text.contains('failed host lookup') ||
          text.contains('connection') ||
          text.contains('network');
      throw CloudBackupFailure(
        looksOffline
            ? CloudBackupFailureKind.offline
            : CloudBackupFailureKind.unknown,
        detail: '$error',
      );
    }
  }

  /// `42P01` is "relation does not exist" and `42501` is "insufficient
  /// privilege"; PostgREST also reports an RLS refusal as `PGRST301`. All
  /// three mean the same thing in practice here — the one-time setup SQL
  /// has not been run — so they get a message that says so instead of
  /// "something went wrong".
  CloudBackupFailureKind _kindOf(sb.PostgrestException error) {
    return switch (error.code) {
      '42P01' ||
      '42501' ||
      'PGRST301' ||
      'PGRST205' =>
        CloudBackupFailureKind.notProvisioned,
      'PGRST116' => CloudBackupFailureKind.noBackupYet,
      _ => CloudBackupFailureKind.unknown,
    };
  }
}
