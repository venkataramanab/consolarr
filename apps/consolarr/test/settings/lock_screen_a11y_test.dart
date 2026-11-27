// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/presentation/app_lock_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';

/// Every lock screen state under the full matrix (sizes x text scale x
/// locales, including `ar` and `en_XA` at 320x568 and scale 2.0) with the
/// accessibility guideline checks.
Widget _gate(HarnessVariant v, ScreenHarness h) =>
    h.screen(v, const AppLockGate(child: Center(child: Text('content'))));

Future<void> _tapUnlock(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    final button = find.byType(FilledButton);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('locked (prompt pending)', (tester) async {
    await pumpMatrix(
      tester,
      (v) {
        final h = ScreenHarness(stored: lockOn());
        h.base.auth.hold = Completer<DeviceAuthResult>();
        return _gate(v, h);
      },
      variants: harnessMatrix(),
      verify: (v) async => expectAccessible(tester),
    );
  });

  testWidgets('failed attempt', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _gate(
        v,
        ScreenHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
        ),
      ),
      variants: harnessMatrix(),
      verify: (v) async => expectAccessible(tester),
    );
  });

  testWidgets('cool-down', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _gate(
        v,
        ScreenHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
        ),
      ),
      variants: stress,
      verify: (v) async {
        await _tapUnlock(tester, lockMaxAttempts - 1);
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('no biometrics', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _gate(
        v,
        ScreenHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(
            biometrics: false,
            results: [DeviceAuthResult.failed],
          ),
        ),
      ),
      variants: harnessMatrix(),
      verify: (v) async => expectAccessible(tester),
    );
  });

  testWidgets('device lock removed', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _gate(
        v,
        ScreenHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(
            supportResult: DeviceAuthSupport.noSecureLock,
          ),
        ),
      ),
      variants: harnessMatrix(),
      verify: (v) async => expectAccessible(tester),
    );
  });

  testWidgets('device lock removed, confirming the turn-off', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _gate(
        v,
        ScreenHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(
            supportResult: DeviceAuthSupport.noSecureLock,
          ),
        ),
      ),
      variants: stress,
      verify: (v) async {
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('settings could not be read (fail closed)', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _gate(
        v,
        ScreenHarness(store: ThrowingSettingsStore(stored: lockOn())),
      ),
      variants: harnessMatrix(),
      verify: (v) async {
        expect(find.text('content'), findsNothing);
        await expectAccessible(tester);
      },
    );
  });
}
