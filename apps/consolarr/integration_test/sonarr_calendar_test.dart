// SPDX-License-Identifier: GPL-3.0-or-later

// Nightly emulator test: the calendar tab loads against the seeded server.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'sonarr_it_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('calendar tab opens and settles', (tester) async {
    final l10n = await openSonarr(tester);
    await tester.tap(find.text(l10n.sonarrTabCalendar));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text(l10n.sonarrTabCalendar), findsWidgets);
  });
}
