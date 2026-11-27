// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'library_harness.dart';
import 'support.dart';

/// The smallest phone, the two locales that stress layout (pseudo-locale text
/// is ~40% longer; Arabic is right-to-left) and the largest text scale.
final _stress = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
);

Map<String, FakeLibraryNotifier Function()> _states() => {
  'data': () => FakeLibraryNotifier(dataState(fakeSeriesList(12))),
  'long titles': () => FakeLibraryNotifier(
    dataState([
      for (var i = 1; i <= 6; i++)
        fakeSeries(i, title: 'Example Show $i ${'Very Long Title ' * 12}'),
    ]),
  ),
  'offline with cache': () => FakeLibraryNotifier(
    dataState(
      fakeSeriesList(6),
      offlineError: const AppError(ErrorCategory.networkUnreachable),
      age: const Duration(hours: 3),
    ),
  ),
};

void main() {
  for (final mode in LibraryViewMode.values) {
    for (final entry in _states().entries) {
      testWidgets(
        '${mode.name}: ${entry.key} at 320x568, scale 2.0, ar and en_XA: no '
        'overflow and accessible',
        (tester) async {
          await pumpMatrix(
            tester,
            (v) => libraryApp(v, notifier: entry.value(), mode: mode),
            variants: _stress,
            verify: (v) => expectAccessible(tester),
          );
        },
      );
    }
  }
}
