import 'package:drift/drift.dart';
import 'package:drift/native.dart';

QueryExecutor createTestingExecutor() => NativeDatabase.memory();
