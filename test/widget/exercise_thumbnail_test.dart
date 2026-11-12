import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/library/presentation/widgets/exercise_media.dart';

/// A bundled picture is decoded at the size it is shown, not its full
/// 600×400.
void main() {
  const String asset =
      'assets/images/exercises/free_exercise_db/3_4_Sit-Up_0.jpg';

  Future<ImageProvider> providerFor(
    WidgetTester tester, {
    String url = asset,
    double? decodeWidth,
    double ratio = 2,
  }) async {
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 56,
          height: 56,
          child: ExerciseThumbnail(
            url: url,
            fallbackIcon: Icons.fitness_center,
            decodeWidth: decodeWidth,
          ),
        ),
      ),
    );
    // The picture is read and decoded off the test's fake clock.
    for (int i = 0; i < 20 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    return tester.widget<Image>(find.byType(Image)).image;
  }

  testWidgets('with a decode width, at that width in device pixels',
      (tester) async {
    final ImageProvider image =
        await providerFor(tester, decodeWidth: 84, ratio: 2);

    expect(image, isA<ResizeImage>());
    expect((image as ResizeImage).width, 168);
    expect(image.height, isNull, reason: 'the shape is kept');
  });

  testWidgets('without one, at full size, as before', (tester) async {
    final ImageProvider image = await providerFor(tester);

    expect(image, isA<AssetImage>());
  });
}
