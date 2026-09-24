import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/services/data_export_service.dart';
import 'package:ironyx/features/backup/data/supabase_cloud_backup_service.dart';
import 'package:ironyx/features/backup/domain/cloud_backup_service.dart';
import 'package:ironyx/features/settings/domain/export_envelope.dart';

Matcher _failsAs(CloudBackupFailureKind kind) => throwsA(
      isA<CloudBackupFailure>().having((f) => f.kind, 'kind', kind),
    );

/// A gzip stream that inflates to [length] zero bytes. Compresses ~1000:1,
/// which is the whole point of a decompression bomb.
String _encodedZeros(int length) =>
    base64Encode(gzip.encode(Uint8List(length)));

void main() {
  group('backup payload encoding', () {
    test('round-trips an export envelope, including non-ASCII text', () {
      const String json = '{"formatVersion":1,"note":"تمرين الصدر 💪"}';
      expect(decodeBackupPayload(encodeBackupPayload(json)), json);
    });

    test('round-trips an empty payload', () {
      expect(decodeBackupPayload(encodeBackupPayload('')), '');
    });

    test('refuses to upload a payload that compresses past the limit',
        () async {
      // Random letters barely compress, so this lands well above 5 MiB once
      // gzipped and base64-encoded.
      final Random random = Random(42);
      final String incompressible = String.fromCharCodes(
        List<int>.generate(9 * 1024 * 1024, (_) => 97 + random.nextInt(26)),
      );
      expect(
        () => encodeBackupPayload(incompressible),
        _failsAs(CloudBackupFailureKind.tooLarge),
      );
      // Production runs this in a background isolate. The typed failure has
      // to survive the trip back, or `_guard` would report it as `unknown`.
      await expectLater(
        compute(encodeBackupPayload, incompressible),
        _failsAs(CloudBackupFailureKind.tooLarge),
      );
    });
  });

  group('backup payload decoding treats the download as untrusted', () {
    test('text that is not base64 is corrupt', () {
      expect(
        () => decodeBackupPayload('not base64 at all!'),
        _failsAs(CloudBackupFailureKind.corrupt),
      );
    });

    test('base64 that is not gzip is corrupt', () {
      expect(
        () => decodeBackupPayload(base64Encode(utf8.encode('{"a":1}'))),
        _failsAs(CloudBackupFailureKind.corrupt),
      );
    });

    test(
        'a truncated gzip stream gets past decoding but is rejected by the '
        'envelope parser', () {
      // dart:io's zlib decoder does not verify the gzip trailer, so a
      // download cut short decodes to a prefix of the JSON instead of
      // throwing (true of `gzip.decode` as well). The envelope parser is
      // what catches it, and `restoreFromCloud` maps that to `corrupt` — a
      // truncated backup can never be half-applied.
      const DataExportService service = DataExportService();
      final String json = '{"formatVersion":${DataExportService.formatVersion},'
          '"tables":{"workouts_table":[${'{"id":"w"},' * 50}{"id":"x"}]}}';
      final List<int> whole = gzip.encode(utf8.encode(json));
      final String decoded = decodeBackupPayload(
        base64Encode(whole.sublist(0, whole.length ~/ 2)),
      );

      expect(json, startsWith(decoded));
      expect(decoded.length, lessThan(json.length));
      expect(
        () => service.parseImport(decoded),
        throwsA(isA<ImportValidationException>()),
      );
    });

    test('gzip that is not UTF-8 is corrupt', () {
      expect(
        () => decodeBackupPayload(
          base64Encode(gzip.encode(<int>[0xff, 0xfe, 0xfd])),
        ),
        _failsAs(CloudBackupFailureKind.corrupt),
      );
    });

    test('an encoded payload over the storage limit is refused unread', () {
      expect(
        () => decodeBackupPayload('A' * (kMaxBackupPayloadBytes + 4)),
        _failsAs(CloudBackupFailureKind.corrupt),
      );
    });

    test('decompressing exactly to the limit is allowed', () {
      expect(
        decodeBackupPayload(_encodedZeros(kMaxBackupDecodedBytes)).length,
        kMaxBackupDecodedBytes,
      );
    });

    test('a gzip bomb one byte past the limit is stopped', () {
      final String bomb = _encodedZeros(kMaxBackupDecodedBytes + 1);
      // Small on the wire — this is what makes it dangerous.
      expect(bomb.length, lessThan(kMaxBackupPayloadBytes));
      expect(
        () => decodeBackupPayload(bomb),
        _failsAs(CloudBackupFailureKind.corrupt),
      );
    });
  });
}
