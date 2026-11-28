// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard_refreshed is sampled: one report per session', () {
    final gate = DashboardRefreshReportGate();
    expect(gate.tryTake(), isTrue);
    expect(gate.tryTake(), isFalse);
    expect(gate.tryTake(), isFalse);
  });

  test('the gate lives for the session (one instance per container)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(dashboardRefreshReportProvider).tryTake(), isTrue);
    expect(c.read(dashboardRefreshReportProvider).tryTake(), isFalse);
    final other = ProviderContainer();
    addTearDown(other.dispose);
    expect(other.read(dashboardRefreshReportProvider).tryTake(), isTrue);
  });
}
