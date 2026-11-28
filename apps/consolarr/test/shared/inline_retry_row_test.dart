// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/widgets/inline_retry_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

final _message = String.fromCharCodes('could not read'.codeUnits);
final _retry = String.fromCharCodes('try again'.codeUnits);

void main() {
  testWidgets('shows the message, retries on tap, accessible in the matrix', (
    tester,
  ) async {
    var retries = 0;
    await pumpMatrix(
      tester,
      (v) => harnessApp(
        v,
        Scaffold(
          body: InlineRetryRow(
            message: _message,
            retryLabel: _retry,
            onRetry: () => retries++,
          ),
        ),
      ),
      variants: harnessMatrix(
        sizes: const [Size(320, 568)],
        textScales: const [2],
      ),
      verify: (v) async {
        expect(find.text(_message), findsOneWidget);
        await expectAccessible(tester);
        await tester.tap(find.text(_retry));
        await tester.pump();
      },
    );
    expect(
      retries,
      harnessMatrix(
        sizes: const [Size(320, 568)],
        textScales: const [2],
      ).length,
    );
  });
}
