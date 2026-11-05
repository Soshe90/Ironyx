import 'package:flutter/services.dart';

/// Turns whatever a keyboard typed into a number field into the ASCII
/// digits and `.` that `int.parse`/`double.parse` read.
///
/// Keyboards disagree about numbers. Many European layouts, and Samsung's
/// in several languages, put a comma on the decimal key. Arabic keyboards
/// can send Arabic-Indic digits (٠١٢…) and the Arabic decimal separator
/// (٫), and Persian ones Extended Arabic-Indic digits (۰۱۲…). The fields
/// used to accept only ASCII digits and `.`, so "82,5" lost its comma as
/// it was typed and became 825, and Arabic digits did not appear at all.
///
/// A comma is always read as a decimal mark, never as a thousands
/// separator. Every number typed in this app is small (a weight, a count,
/// a few minutes), and "1,5" meaning one and a half is far likelier than
/// "1,500" meaning fifteen hundred.
String normalizeNumberInput(String text) {
  final StringBuffer out = StringBuffer();
  for (final int rune in text.runes) {
    out.write(_normalizeRune(rune));
  }
  return out.toString();
}

/// Reads a decimal number as a person typed it: see [normalizeNumberInput].
/// Null for empty text, for text that is not one number, and for `NaN` and
/// infinities, which `double.tryParse` would otherwise accept.
double? parseDecimalInput(String text) {
  final double? value = double.tryParse(normalizeNumberInput(text).trim());
  return value != null && value.isFinite ? value : null;
}

/// Reads a whole number as a person typed it: see [normalizeNumberInput].
int? parseIntegerInput(String text) =>
    int.tryParse(normalizeNumberInput(text).trim());

/// Keeps a number field to digits, plus one kind of decimal mark when
/// [decimal], after mapping what the keyboard sent onto them (see
/// [normalizeNumberInput]).
///
/// Anything else is dropped as it is typed or pasted: signs, letters,
/// spaces, exponents. A second decimal mark is kept, not dropped, so that
/// "8.5.5" is refused as a whole rather than silently read as 8.55.
class NumberInputFormatter extends TextInputFormatter {
  const NumberInputFormatter.decimal() : decimal = true;
  const NumberInputFormatter.integer() : decimal = false;

  final bool decimal;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String text = newValue.text;
    final StringBuffer out = StringBuffer();
    // For each code unit of [text], how many output characters precede it,
    // so the cursor and the keyboard's composing range can be moved onto
    // the same characters after some are dropped.
    final List<int> kept = List<int>.filled(text.length + 1, 0);

    int i = 0;
    int written = 0;
    for (final int rune in text.runes) {
      final int width = rune > 0xFFFF ? 2 : 1;
      final String mapped = _normalizeRune(rune);
      final bool keep = _isDigit(mapped) || (decimal && mapped == '.');
      for (int k = 0; k < width; k++) {
        kept[i + k] = written;
      }
      if (keep) {
        out.write(mapped);
        written++;
      }
      i += width;
    }
    kept[text.length] = written;

    final String result = out.toString();
    if (result == text) return newValue;

    int move(int offset) =>
        offset < 0 ? offset : kept[offset.clamp(0, text.length)];

    final TextSelection selection = newValue.selection;
    final TextRange composing = newValue.composing;
    return TextEditingValue(
      text: result,
      selection: selection.isValid
          ? selection.copyWith(
              baseOffset: move(selection.baseOffset),
              extentOffset: move(selection.extentOffset),
            )
          : selection,
      composing: composing.isValid && !composing.isCollapsed
          ? TextRange(start: move(composing.start), end: move(composing.end))
          : TextRange.empty,
    );
  }

  static bool _isDigit(String s) =>
      s.length == 1 && s.codeUnitAt(0) >= 0x30 && s.codeUnitAt(0) <= 0x39;
}

String _normalizeRune(int rune) {
  // Arabic-Indic digits ٠-٩.
  if (rune >= 0x0660 && rune <= 0x0669) {
    return String.fromCharCode(0x30 + rune - 0x0660);
  }
  // Extended Arabic-Indic (Persian, Urdu) digits ۰-۹.
  if (rune >= 0x06F0 && rune <= 0x06F9) {
    return String.fromCharCode(0x30 + rune - 0x06F0);
  }
  return switch (rune) {
    0x2C || // , comma
    0x066B || // ٫ Arabic decimal separator
    0x060C => // ، Arabic comma, the comma key on Arabic layouts
      '.',
    _ => String.fromCharCode(rune),
  };
}
