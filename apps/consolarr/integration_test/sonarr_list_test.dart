// SPDX-License-Identifier: GPL-3.0-or-later

// Nightly emulator test: the seeded Sonarr library lists series.

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'sonarr_it_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('library shows the seeded series', (tester) async {
    await openSonarr(tester);
    await pumpUntil(tester, find.byType(PosterCard));
    expect(find.byType(PosterCard), findsWidgets);
  });
}
