// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

class _Host extends StatelessWidget {
  const _Host({required this.onConfirm, required this.result});

  final Future<AppError?> Function(ArrQueueRemovalChoice) onConfirm;
  final List<bool> result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => result.add(
          await showArrQueueRemovalDialog(
            context: context,
            itemLabel: 'Example Show 1',
            serviceName: 'Sonarr',
            kind: ServiceKind.sonarr,
            onConfirm: onConfirm,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _open(
  WidgetTester tester,
  Future<AppError?> Function(ArrQueueRemovalChoice) onConfirm,
  List<bool> result, {
  HarnessVariant variant = _v,
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(
    harnessApp(variant, _Host(onConfirm: onConfirm, result: result)),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('states the consequences in words', (tester) async {
    await _open(tester, (_) async => null, []);
    expect(find.text('Remove from queue?'), findsOneWidget);
    expect(
      find.textContaining('deleted from the download client'),
      findsOneWidget,
    );
    expect(find.textContaining('adds load on your indexers'), findsOneWidget);
    expect(find.textContaining('No new search is started'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('only Sonarr stops tracking it'),
      findsOneWidget,
    );
  });

  for (final entry in {
    'Don\'t blocklist': ArrBlocklistChoice.none,
    'Blocklist and search again': ArrBlocklistChoice.blocklistAndSearch,
    'Blocklist only': ArrBlocklistChoice.blocklistOnly,
  }.entries) {
    testWidgets('choice "${entry.key}" is passed to the callback', (
      tester,
    ) async {
      ArrQueueRemovalChoice? got;
      final result = <bool>[];
      await _open(tester, (c) async {
        got = c;
        return null;
      }, result);
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(got?.blocklist, entry.value);
      expect(got?.removeFromClient, isTrue);
      expect(result, [true]);
      expect(find.text('Remove from queue?'), findsNothing);
    });
  }

  testWidgets('only-in-service choice sends removeFromClient false', (
    tester,
  ) async {
    ArrQueueRemovalChoice? got;
    await _open(tester, (c) async {
      got = c;
      return null;
    }, []);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(got?.removeFromClient, isFalse);
  });

  testWidgets('in progress: buttons disabled, a second tap does not submit', (
    tester,
  ) async {
    final gate = Completer<AppError?>();
    var calls = 0;
    final result = <bool>[];
    await _open(tester, (_) {
      calls++;
      return gate.future;
    }, result);
    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(find.text('Removing…'), findsWidgets);
    await tester.tap(find.text('Remove'), warnIfMissed: false);
    await tester.tap(find.text('Cancel'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Remove from queue?'), findsOneWidget);
    gate.complete(null);
    await tester.pumpAndSettle();
    expect(result, [true]);
  });

  testWidgets('failure shows the cause and offers retry', (tester) async {
    var calls = 0;
    final result = <bool>[];
    await _open(tester, (_) async {
      calls++;
      return calls == 1 ? const AppError(ErrorCategory.timeout) : null;
    }, result);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t remove the item'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(result, [true]);
  });

  testWidgets('a 401 says the API key was rejected, not "retry the login"', (
    tester,
  ) async {
    await _open(
      tester,
      (_) async => const AppError(ErrorCategory.authFailed),
      <bool>[],
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Sonarr rejected the API key.'), findsOneWidget);
    expect(find.textContaining("don't work for the API"), findsOneWidget);
  });

  testWidgets('cancel resolves to false without calling', (tester) async {
    var calls = 0;
    final result = <bool>[];
    await _open(tester, (_) async {
      calls++;
      return null;
    }, result);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(result, [false]);
  });

  testWidgets('layout and accessibility at 320x568, scale 2, ar and en_XA', (
    tester,
  ) async {
    for (final locale in const [Locale('ar'), Locale('en', 'XA')]) {
      final v = HarnessVariant(
        size: const Size(320, 568),
        textScale: 2,
        locale: locale,
        brightness: Brightness.light,
      );
      await tester.pumpWidget(const SizedBox());
      await _open(
        tester,
        (_) async => const AppError(ErrorCategory.timeout),
        [],
        variant: v,
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expectNoFrameworkExceptions(tester, context: v.label);
      await expectAccessible(tester);
    }
  });
}
