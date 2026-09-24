import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/timer_preset_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/features/timer/domain/timer_preset.dart';

import '../helpers/pump_app.dart';

void main() {
  group('TimerPage', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting();
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets(
        'shows quick-start presets and the custom builder; feedback toggles '
        'live in Settings, and saved presets appear only once there are some',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/timer',
        prefs: const {'exercise_seed_version': 999999},
        surfaceSize: const Size(400, 1400),
      );

      expect(find.text('Tabata'), findsOneWidget);
      expect(find.text('HIIT'), findsOneWidget);
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Work (s)'), findsOneWidget);
      expect(find.text('Sound cues'), findsNothing);
      expect(find.text('Haptics'), findsNothing);
      expect(find.text('Saved presets'), findsNothing);
    });

    testWidgets('quick start comes before the saved preset section',
        (tester) async {
      await tester.runAsync(
        () => TimerPresetDao(database).save(
          TimerPresets.tabata().copyWith(id: 'mine', name: 'My EMOM'),
        ),
      );
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/timer',
        prefs: const {'exercise_seed_version': 999999},
        surfaceSize: const Size(400, 1400),
        awaitDatabase: true,
      );
      await tester.pump();

      expect(find.text('Saved presets'), findsOneWidget);
      expect(find.text('My EMOM'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Quick start')).dy,
        lessThan(tester.getTopLeft(find.text('Saved presets')).dy),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });
}
