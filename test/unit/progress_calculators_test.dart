import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/progress/domain/progress_calculators.dart';

void main() {
  group('epleyOneRepMax', () {
    test('returns the actual load for one rep', () {
      expect(epleyOneRepMax(100, 1), 100);
    });

    test('estimates multi-rep max', () {
      expect(epleyOneRepMax(100, 5), closeTo(116.666, 0.001));
    });

    test('rejects zero and invalid measurements', () {
      expect(epleyOneRepMax(0, 5), 0);
      expect(epleyOneRepMax(100, 0), 0);
      expect(epleyOneRepMax(-10, 5), 0);
    });
  });

  group('isPersonalRecord', () {
    test('requires a positive estimate above all previous values', () {
      expect(isPersonalRecord(120, [100, 115]), isTrue);
      expect(isPersonalRecord(115, [100, 115]), isFalse);
      expect(isPersonalRecord(0, []), isFalse);
    });
  });

  group('setVolumeKg', () {
    test('multiplies load and reps', () {
      expect(setVolumeKg(60, 8), 480);
    });

    test('returns zero for bodyweight or invalid sets', () {
      expect(setVolumeKg(0, 10), 0);
      expect(setVolumeKg(50, 0), 0);
      expect(setVolumeKg(50, -1), 0);
    });
  });
}
