import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/database/tables/exercise_media.dart';
import 'package:ironyx/core/database/tables/exercises.dart';
import 'package:ironyx/features/library/presentation/widgets/exercise_detail_sheet.dart';
import 'package:ironyx/features/library/presentation/widgets/exercise_media.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// The detail sheet shows every picture of an exercise (the catalogue ships
/// a start and an end position), one at a time, swiped between.
/// Lets the sheet and page animations finish. Not `pumpAndSettle`: while a
/// picture's file is read the thumbnail shows a spinning progress
/// indicator, and under the test clock that read need not finish, so the
/// screen never "settles". Each page is found by its key, not its pixels.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // Real bundled assets, so the pictures actually load.
  const String start =
      'assets/images/exercises/ironyx/banded-hip-abduction_0.jpg';
  const String end =
      'assets/images/exercises/ironyx/banded-hip-abduction_1.jpg';

  ExerciseMedia image(String id, String? localAsset, {int sortOrder = 0}) =>
      ExerciseMedia(
        id: id,
        exerciseId: 'ex',
        type: ExerciseMediaType.image,
        localAsset: localAsset,
        sortOrder: sortOrder,
      );

  ExerciseDetail detail(List<ExerciseMedia> media) {
    final DateTime now = DateTime(2026, 11, 5);
    return ExerciseDetail(
      exercise: Exercise(
        id: 'ex',
        slug: 'banded-hip-abduction',
        name: 'Banded Hip Abduction',
        description: '',
        category: ExerciseCategory.strength,
        difficulty: Difficulty.beginner,
        movementPattern: MovementPattern.other,
        isUnilateral: false,
        isBodyweight: false,
        isTimeBased: false,
        seedVersion: 22,
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      muscles: const [],
      equipment: const [],
      instructions: const [],
      aliases: const [],
      media: media,
      tags: const [],
    );
  }

  Future<void> openSheet(
    WidgetTester tester,
    List<ExerciseMedia> media, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseDetailProvider('ex')
              .overrideWith((ref) async => detail(media)),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Center(
              child: ExerciseInfoTapTarget(
                exerciseId: 'ex',
                child: Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  final Finder swiper =
      find.byKey(const ValueKey<String>('exercise-picture-swiper'));
  final Finder dots =
      find.byKey(const ValueKey<String>('exercise-picture-dots'));
  Finder showing(String asset) => find.byKey(ValueKey<String>(asset));

  /// The dot colours, in reading order: white is the picture on screen.
  List<Color?> dotColours(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(
        find.descendant(of: dots, matching: find.byType(AnimatedContainer)),
      )
      .map((AnimatedContainer c) => (c.decoration as BoxDecoration?)?.color)
      .toList();

  group('exercisePictures', () {
    test('keeps images in order and drops videos and empty entries', () {
      final List<ExerciseMedia> media = <ExerciseMedia>[
        image('a', start),
        const ExerciseMedia(
          id: 'v',
          exerciseId: 'ex',
          type: ExerciseMediaType.video,
          url: 'https://www.youtube.com/watch?v=abc',
          sortOrder: 1,
        ),
        image('blank', '', sortOrder: 2),
        image('none', null, sortOrder: 3),
        image('b', end, sortOrder: 4),
      ];
      expect(exercisePictures(media), <String>[start, end]);
      expect(exercisePictures(const <ExerciseMedia>[]), isEmpty);
    });
  });

  testWidgets('a start and an end picture are swiped between, with dots',
      (tester) async {
    await openSheet(tester, [image('a', start), image('b', end, sortOrder: 1)]);

    expect(swiper, findsOneWidget);
    expect(showing(start), findsOneWidget);
    expect(dotColours(tester), <Color>[
      Colors.white,
      Colors.white.withValues(alpha: 0.45),
    ]);

    // Started on the search badge in the middle of the picture: it used to
    // swallow the touch, so the swipe never reached the pictures.
    await tester.dragFrom(
      tester.getCenter(
        find.byKey(const ValueKey<String>('exercise-search-badge')),
      ),
      const Offset(-400, 0),
    );
    await settle(tester);

    expect(showing(end), findsOneWidget);
    expect(showing(start), findsNothing);
    expect(dotColours(tester), <Color>[
      Colors.white.withValues(alpha: 0.45),
      Colors.white,
    ]);

    // There is nothing past the end picture.
    await tester.drag(swiper, const Offset(-400, 0));
    await settle(tester);
    expect(showing(end), findsOneWidget);

    await tester.drag(swiper, const Offset(400, 0));
    await settle(tester);
    expect(showing(start), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Arabic the end picture comes in from the left',
      (tester) async {
    await openSheet(
      tester,
      [image('a', start), image('b', end, sortOrder: 1)],
      locale: const Locale('ar'),
    );

    // The left-to-right swipe that goes back in English goes forward here.
    await tester.drag(swiper, const Offset(400, 0));
    await settle(tester);
    expect(showing(end), findsOneWidget);
  });

  testWidgets('a screen reader hears which position is showing',
      (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await openSheet(
      tester,
      [image('a', start), image('b', end, sortOrder: 1)],
      locale: const Locale('ar'),
    );

    expect(find.bySemanticsLabel('وضعية البداية'), findsOneWidget);
    await tester.drag(swiper, const Offset(400, 0));
    await settle(tester);
    expect(find.bySemanticsLabel('وضعية النهاية'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('more than two pictures are numbered for a screen reader',
      (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await openSheet(tester, [
      image('a', start),
      image('b', end, sortOrder: 1),
      image('c', start, sortOrder: 2),
    ]);

    expect(find.bySemanticsLabel('Picture 1 of 3'), findsOneWidget);
    expect(dotColours(tester), hasLength(3));
    semantics.dispose();
  });

  testWidgets('one picture shows as before: no swiping, no dots',
      (tester) async {
    await openSheet(tester, [image('a', start)]);

    expect(showing(start), findsNothing,
        reason: 'the single picture is not a swiper page');
    expect(find.byType(ExerciseThumbnail), findsOneWidget);
    expect(swiper, findsNothing);
    expect(dots, findsNothing);
  });

  testWidgets('a tap on the pictures still searches YouTube', (tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    const MethodChannel channel =
        MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (MethodCall call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await openSheet(tester, [image('a', start), image('b', end, sortOrder: 1)]);
    await tester.tap(swiper);
    await settle(tester);

    final MethodCall launch = calls.singleWhere(
      (MethodCall c) => c.method == 'launch',
    );
    expect(
      (launch.arguments as Map<Object?, Object?>)['url'],
      contains('youtube.com/results?search_query=Banded'),
    );
  });
}
