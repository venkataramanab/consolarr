// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

final _decimalDigit = RegExp(r'^\p{Nd}$', unicode: true);

/// The value (0-9) of [rune] when it is a Unicode decimal digit (`\p{Nd}`):
/// ASCII, Arabic-Indic, Persian, Devanagari, full-width and so on; `null`
/// otherwise. Decimal digits come in consecutive runs of ten starting at zero,
/// so the value is the distance from the start of the run, modulo ten.
int? decimalDigitValue(int rune) {
  bool isNd(int r) => _decimalDigit.hasMatch(String.fromCharCode(r));
  if (!isNd(rune)) return null;
  var start = rune;
  // A run is at most a few sets of ten long; the bound keeps this constant.
  for (var i = 0; i < 100 && start > 0 && isNd(start - 1); i++) {
    start--;
  }
  return (rune - start) % 10;
}

/// [text] with every decimal digit of any script turned into ASCII `0-9`;
/// other characters stay.
String normalizeDigits(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final v = decimalDigitValue(rune);
    out.write(v == null ? String.fromCharCode(rune) : '$v');
  }
  return out.toString();
}

/// Keeps only decimal digits of any script and stores them as ASCII, so the
/// field accepts the digits the user's keyboard produces (`digitsOnly` drops
/// Arabic-Indic ones) and the value parses with `int.tryParse`.
class AnyDigitsFormatter extends TextInputFormatter {
  const AnyDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final kept = StringBuffer();
    var cursor = 0;
    var index = 0;
    for (final rune in newValue.text.runes) {
      final width = String.fromCharCode(rune).length;
      final v = decimalDigitValue(rune);
      if (v != null) kept.write('$v');
      index += width;
      if (index <= newValue.selection.extentOffset && v != null) cursor++;
    }
    final text = kept.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: cursor > text.length ? text.length : cursor,
      ),
    );
  }
}
