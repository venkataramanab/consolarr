// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/time/current_day.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('visibility is counted by owner: a hidden screen cannot stop '
      'the midnight timer of a visible one', (tester) async {
    var now = DateTime(2026, 5, 1, 23, 59, 50);
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);
    final day = container.read(currentDayProvider.notifier);
    final a = Object();
    final b = Object();

    day
      ..setVisible(true, owner: a)
      ..setVisible(true, owner: b)
      // b is hidden (another tab) while a stays visible.
      ..setVisible(false, owner: b);
    now = DateTime(2026, 5, 2, 0, 0, 5);
    await tester.pump(const Duration(seconds: 15));
    expect(container.read(currentDayProvider), DateTime.utc(2026, 5, 2));

    // Nobody visible: no timer, the day does not move.
    day.setVisible(false, owner: a);
    now = DateTime(2026, 5, 3, 0, 0, 5);
    await tester.pump(const Duration(hours: 24));
    expect(container.read(currentDayProvider), DateTime.utc(2026, 5, 2));

    // Visible again: catches up at once.
    day.setVisible(true, owner: b);
    expect(container.read(currentDayProvider), DateTime.utc(2026, 5, 3));
    day.setVisible(false, owner: b);
  });
}
