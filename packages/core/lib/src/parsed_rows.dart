// SPDX-License-Identifier: GPL-3.0-or-later

/// The rows of a list payload that parsed, plus how many were skipped because
/// they were malformed. Only the count is ever reported (never row content).
class ParsedRows<T> {
  const ParsedRows(this.items, {this.skipped = 0});

  final List<T> items;

  /// Rows dropped as malformed.
  final int skipped;
}

/// Parses every element of [rows] with [parse], skipping elements that throw
/// [FormatException] (or are not accepted by [parse]).
///
/// When [rows] is non-empty and *none* parsed, the payload is not the expected
/// shape (wrong service, an HTML page): that throws [FormatException] so the
/// caller reports `parse_error` instead of an empty list.
ParsedRows<T> parseRowsTolerant<T>(
  Iterable<Object?> rows,
  T Function(Object? row) parse,
) {
  final items = <T>[];
  var skipped = 0;
  for (final row in rows) {
    try {
      items.add(parse(row));
    } on FormatException {
      skipped++;
    } on TypeError {
      skipped++;
    }
  }
  if (items.isEmpty && skipped > 0) {
    throw const FormatException('no row could be parsed');
  }
  return ParsedRows(items, skipped: skipped);
}
