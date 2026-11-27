// SPDX-License-Identifier: GPL-3.0-or-later

// Nightly emulator test: a series opens its detail screen.

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'sonarr_it_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping a series opens its detail', (tester) async {
    await openSonarr(tester);
    await pumpUntil(tester, find.byType(PosterCard));
    await tester.tap(find.byType(PosterCard).first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    // The library is covered by the detail screen (a full-screen route).
    expect(find.byType(PosterCard), findsNothing);
  });
}
