import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/number_input.dart';

// Escapes rather than literal Arabic and Persian digits, so the source is
// unambiguous whatever editor or terminal shows it.
const String _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
const String _arabicDecimal = '٫'; // ٫
const String _arabicComma = '،'; // ،

/// 82.5 typed on an Arabic keyboard: ٨٢٫٥.
const String _arabic82point5 = '٨٢٫٥';

void main() {
  group('normalizeNumberInput', () {
    test('maps Arabic-Indic and Extended Arabic-Indic digits to ASCII', () {
      expect(normalizeNumberInput(_arabicDigits), '0123456789');
      expect(normalizeNumberInput(_persianDigits), '0123456789');
    });

    test('reads a comma, the Arabic decimal mark and comma as a point', () {
      expect(normalizeNumberInput('82,5'), '82.5');
      expect(normalizeNumberInput('82${_arabicDecimal}5'), '82.5');
      expect(normalizeNumberInput('82${_arabicComma}5'), '82.5');
    });

    test('leaves everything else alone', () {
      expect(normalizeNumberInput('12.5'), '12.5');
      expect(normalizeNumberInput('-1e3 x'), '-1e3 x');
      expect(normalizeNumberInput(''), '');
    });
  });

  group('parseDecimalInput', () {
    test('reads numbers typed in any of those ways', () {
      expect(parseDecimalInput('82.5'), 82.5);
      expect(parseDecimalInput(' 82,5 '), 82.5);
      expect(parseDecimalInput(_arabic82point5), 82.5);
      expect(parseDecimalInput('7'), 7);
    });

    test('is null for empty, malformed and non-finite text', () {
      for (final String text in <String>[
        '',
        '  ',
        '8..5',
        '8,5,5',
        'abc',
        'NaN',
        'Infinity',
        '1e999',
      ]) {
        expect(parseDecimalInput(text), isNull, reason: '"$text"');
      }
    });
  });

  group('parseIntegerInput', () {
    test('reads ASCII and Arabic digits, and nothing with a fraction', () {
      expect(parseIntegerInput('120'), 120);
      expect(parseIntegerInput('١٢٠'), 120);
      expect(parseIntegerInput(' 5 '), 5);
      expect(parseIntegerInput('1,5'), isNull);
      expect(parseIntegerInput(''), isNull);
    });
  });

  group('NumberInputFormatter', () {
    TextEditingValue format(
      TextInputFormatter formatter,
      String text, {
      int? cursor,
      TextRange composing = TextRange.empty,
    }) =>
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: cursor ?? text.length),
            composing: composing,
          ),
        );

    const NumberInputFormatter decimal = NumberInputFormatter.decimal();
    const NumberInputFormatter integer = NumberInputFormatter.integer();

    test('decimal keeps digits and decimal marks, as points', () {
      expect(format(decimal, '82,5').text, '82.5');
      expect(format(decimal, _arabic82point5).text, '82.5');
      expect(format(decimal, '-8 2.5kg').text, '82.5');
      // A second mark is kept, so the value is refused, not misread.
      expect(format(decimal, '8.5.5').text, '8.5.5');
    });

    test('integer keeps digits only, after mapping them', () {
      expect(format(integer, '١٢٠').text, '120');
      expect(format(integer, '1,5').text, '15');
      expect(format(integer, '-3').text, '3');
    });

    test('an unchanged value is passed through as it came', () {
      const TextEditingValue value = TextEditingValue(
        text: '82.5',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 4),
      );
      expect(
        decimal.formatEditUpdate(TextEditingValue.empty, value),
        same(value),
      );
    });

    test('the cursor stays after the same character', () {
      // Cursor after "8-2", before ",5": the dropped "-" moves it back one.
      final TextEditingValue out = format(decimal, '8-2,5', cursor: 3);
      expect(out.text, '82.5');
      expect(out.selection, const TextSelection.collapsed(offset: 2));

      final TextEditingValue end = format(decimal, ' 82,5 ');
      expect(end.selection, const TextSelection.collapsed(offset: 4));
    });

    test('a composing range is moved onto the same characters', () {
      final TextEditingValue out = format(
        decimal,
        'x$_arabic82point5',
        composing: const TextRange(start: 1, end: 5),
      );
      expect(out.text, '82.5');
      expect(out.composing, const TextRange(start: 0, end: 4));
    });

    test('characters outside the basic plane are dropped cleanly', () {
      // U+1F600 is two UTF-16 code units; the cursor sits after it.
      final TextEditingValue out = format(decimal, '8\u{1F600}2', cursor: 3);
      expect(out.text, '82');
      expect(out.selection, const TextSelection.collapsed(offset: 1));
    });

    test('a selection that is not set stays unset', () {
      final TextEditingValue out = decimal.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '8,5'),
      );
      expect(out.text, '8.5');
      expect(out.selection.isValid, isFalse);
    });
  });
}
