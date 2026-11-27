// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:l10n/l10n.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('formatBytes picks the unit and rounds', () {
    expect(formatBytes(en, 0), '0 B');
    expect(formatBytes(en, 1023), '1,023 B');
    expect(formatBytes(en, 1024), '1 KB');
    expect(formatBytes(en, 1536), '1.5 KB');
    expect(formatBytes(en, 5 * 1024 * 1024), '5 MB');
    expect(formatBytes(en, 3 * 1024 * 1024 * 1024), '3 GB');
    expect(formatBytes(en, 2 * 1024 * 1024 * 1024 * 1024), '2 TB');
    expect(formatBytes(en, -5), '0 B');
  });

  test('formatSpeed appends the rate unit', () {
    expect(formatSpeed(en, 1536), '1.5 KB/s');
  });

  test('formatDuration uses two units at most', () {
    expect(formatDuration(en, const Duration(seconds: 45)), '45s');
    expect(formatDuration(en, const Duration(minutes: 12, seconds: 5)), '12m');
    expect(formatDuration(en, const Duration(hours: 3, minutes: 5)), '3h 5m');
    expect(formatDuration(en, const Duration(days: 2, hours: 4)), '2d 4h');
    expect(formatDuration(en, const Duration(seconds: -3)), '0s');
  });

  test('formatting is locale-aware', () {
    expect(formatBytes(ar, 1536), isNot(formatBytes(en, 1536)));
    expect(formatBytes(ar, 1536), contains('ك.ب'));
  });
}
