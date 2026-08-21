import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/daos/program_dao.dart';
import '../../../core/database/database_providers.dart';

part 'program_providers.g.dart';

/// All programs with their day counts, for the programs list.
@Riverpod(keepAlive: true)
Stream<List<ProgramSummary>> programSummaries(Ref ref) =>
    ref.watch(programDaoProvider).watchAll();

/// One program with its ordered day-templates, for the detail view.
@riverpod
Future<ProgramDetail?> programDetail(Ref ref, String programId) =>
    ref.watch(programDaoProvider).getDetail(programId);
