// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'library_harness.dart';
import 'support.dart';

/// 2 sizes x 2 text scales x 3 locales x 2 themes = 24 variants.
final _full = harnessMatrix(sizes: const [Size(320, 568), Size(412, 915)]);

Map<String, FakeLibraryNotifier Function()> _states() => {
  'loading': () => FakeLibraryNotifier(null),
  'data': () => FakeLibraryNotifier(dataState(fakeSeriesList(12))),
  'empty': () => FakeLibraryNotifier(dataState(const [])),
  'offline with cache': () => FakeLibraryNotifier(
    dataState(
      fakeSeriesList(6),
      offlineError: const AppError(ErrorCategory.networkUnreachable),
      age: const Duration(hours: 3),
    ),
  ),
  'failure': () => FakeLibraryNotifier(
    const LibraryFailure(AppError(ErrorCategory.authFailed)),
  ),
};

void main() {
  for (final mode in LibraryViewMode.values) {
    for (final entry in _states().entries) {
      testWidgets(
        '${mode.name}: ${entry.key}: full matrix, no overflow and accessible',
        (tester) async {
          await pumpMatrix(
            tester,
            (v) => libraryApp(v, notifier: entry.value(), mode: mode),
            variants: _full,
            verify: (v) => expectAccessible(tester),
          );
        },
      );
    }
  }
}
