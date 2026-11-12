import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/search_fold.dart';

void main() {
  test('containsArabic tells an Arabic query from a Latin one', () {
    expect(containsArabic('ضغط'), isTrue);
    expect(containsArabic('bench ضغط'), isTrue);
    expect(containsArabic('bench press'), isFalse);
    expect(containsArabic('12 kg'), isFalse);
    expect(containsArabic(''), isFalse);
  });

  test('an Arabic query matches a name as typed without its marks', () {
    expect(matchesSearch('ضغط بار مستو', <String>['ضغط بار على مقعد مستوٍ']),
        isTrue);
    expect(matchesSearch('رفرفه اماميه', <String>['رفرفة أماميّة']), isTrue);
    expect(matchesSearch('سكوات', <String>['ضغط بار']), isFalse);
  });
}
