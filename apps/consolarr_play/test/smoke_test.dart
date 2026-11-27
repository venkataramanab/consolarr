// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('play entry point renders the shared app', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ConsolarrApp()));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsWidgets);
    // Unmount so the database stream's cleanup timer fires before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
