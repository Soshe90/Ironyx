import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/services/data_export_service.dart';
import 'package:ironyx/features/settings/domain/export_envelope.dart';
import 'package:ironyx/features/settings/presentation/widgets/data_management_section.dart';

/// A picked file with given contents and reported size, counting reads.
final class _File extends PlatformFile {
  _File(this.bytes, {int? reportedSize}) : size = reportedSize ?? bytes.length;

  final Uint8List bytes;
  final int size;
  int reads = 0;

  @override
  String get name => 'backup.json';

  @override
  Uri get uri => Uri.file('/backup.json');

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => size;

  @override
  Future<int> length() async => size;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(bytes);
}

/// Import reads a picked file through `readImportFile`: size first, then
/// decode and validate off the UI isolate.
void main() {
  const DataExportService service = DataExportService();

  test('a file over the limit is refused before it is read', () async {
    final _File file = _File(Uint8List(0), reportedSize: kMaxImportBytes + 1);

    await expectLater(
      readImportFile(service, file),
      throwsA(isA<ImportFileTooLargeException>()),
    );
    expect(file.reads, 0, reason: 'it was read whole first');
  });

  test('a real export reads back as one', () async {
    final AppDatabase database = AppDatabase.forTesting();
    final String json = await service.buildJsonExport(database);
    await database.close();

    final ImportEnvelope envelope = await readImportFile(
      service,
      _File(Uint8List.fromList(utf8.encode(json))),
    );
    expect(envelope.tables, isNotEmpty);
  });

  test('a file that is not an export says so, from the background', () async {
    await expectLater(
      readImportFile(service, _File(Uint8List.fromList(utf8.encode('{}')))),
      throwsA(
        isA<ImportValidationException>()
            .having((e) => e.problem, 'problem', ImportProblem.notAnExport),
      ),
    );
  });

  test('bytes that are not text cannot be read', () async {
    await expectLater(
      readImportFile(service, _File(Uint8List.fromList(<int>[0xff, 0xfe]))),
      throwsA(isA<FormatException>()),
    );
  });
}
