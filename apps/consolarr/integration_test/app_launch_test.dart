// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/main.dart' as app;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and shows the home screen', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsWidgets);
  });
}
