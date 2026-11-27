// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:core/core.dart';

/// One page of a paged `*arr` resource (`{page, pageSize, totalRecords,
/// records}`), shared by queue and wanted lists.
class ArrPage<T> {
  const ArrPage({
    required this.records,
    this.page = 1,
    this.pageSize = 0,
    this.totalRecords = 0,
    this.skipped = 0,
  });

  /// Parses [json] with [parse] per record; malformed records are skipped and
  /// counted. Throws [FormatException] for a non-object body or when no
  /// record at all parses.
  static ArrPage<T> fromJson<T>(
    Object? json,
    T Function(Map<String, Object?> json) parse,
  ) {
    final m = JsonRead.map(json);
    if (m == null) throw const FormatException('expected an object');
    final records = m['records'];
    if (records is! List)
      throw const FormatException('records must be an array');
    final ParsedRows<T> rows = parseArrList(records, parse);
    return ArrPage(
      records: rows.items,
      page: JsonRead.intOrNull(m, 'page') ?? 1,
      pageSize: JsonRead.integer(m, 'pageSize'),
      totalRecords: JsonRead.intOrNull(m, 'totalRecords') ?? rows.items.length,
      skipped: rows.skipped,
    );
  }

  final List<T> records;
  final int page;
  final int pageSize;
  final int totalRecords;

  /// Records that could not be parsed (count only).
  final int skipped;

  bool get hasMore => page * pageSize < totalRecords && records.isNotEmpty;
}
