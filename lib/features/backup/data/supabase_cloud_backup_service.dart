import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/cloud_backup_service.dart';

/// Compresses and encodes [payload] for upload, refusing a result larger
/// than [kMaxBackupPayloadBytes] (the server would reject it anyway).
///
/// Run via [compute] rather than called directly — gzipping a
/// multi-hundred-KB JSON payload on every backup is real, non-yielding CPU
/// work. `compute`, not `Isolate.run`: browsers have no real isolate
/// primitive to spawn, so `compute` is Flutter's own cross-platform-safe
/// wrapper for exactly this — a true background isolate on native
/// platforms, running inline in place on web rather than failing there.
@visibleForTesting
String encodeBackupPayload(String payload) {
  final String encoded = base64Encode(gzip.encode(utf8.encode(payload)));
  if (encoded.length > kMaxBackupPayloadBytes) {
    throw CloudBackupFailure(
      CloudBackupFailureKind.tooLarge,
      detail: '${encoded.length} bytes',
    );
  }
  return encoded;
}

/// Reverses [encodeBackupPayload]. Throws [CloudBackupFailure] with
/// [CloudBackupFailureKind.corrupt] for anything that is not a valid,
/// in-bounds payload.
///
/// The downloaded row is treated as untrusted input. Both sizes are bounded:
/// the encoded length before any work is done, and the decompressed length
/// *while* decompressing, so a small payload that inflates to gigabytes is
/// stopped after at most one extra chunk instead of after exhausting memory.
@visibleForTesting
String decodeBackupPayload(String encoded) {
  if (encoded.length > kMaxBackupPayloadBytes) {
    throw CloudBackupFailure(
      CloudBackupFailureKind.corrupt,
      detail: 'encoded payload is ${encoded.length} bytes',
    );
  }
  try {
    final BytesBuilder output = BytesBuilder(copy: false);
    final ByteConversionSink sink = gzip.decoder.startChunkedConversion(
      _CappedByteSink(output, kMaxBackupDecodedBytes),
    );
    sink
      ..add(base64Decode(encoded))
      ..close();
    return utf8.decode(output.takeBytes());
  } on Object catch (error) {
    throw CloudBackupFailure(
      CloudBackupFailureKind.corrupt,
      detail: '$error',
    );
  }
}

/// Collects decompressed chunks, throwing as soon as their total passes
/// [_limit].
class _CappedByteSink implements Sink<List<int>> {
  _CappedByteSink(this._output, this._limit);

  final BytesBuilder _output;
  final int _limit;

  @override
  void add(List<int> chunk) {
    if (_output.length + chunk.length > _limit) {
      throw StateError('backup decompresses past $_limit bytes');
    }
    _output.add(chunk);
  }

  @override
  void close() {}
}

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
        final String encoded = await compute(encodeBackupPayload, payload);
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
        return decodeBackupPayload(encoded);
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
  /// "something went wrong". `23514` is a check-constraint violation, and the
  /// only check on `backups` is the payload size limit.
  CloudBackupFailureKind _kindOf(sb.PostgrestException error) {
    return switch (error.code) {
      '23514' => CloudBackupFailureKind.tooLarge,
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
