// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/connection_check.dart';
import 'package:consolarr/features/settings/presentation/connection_check_screen.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';

/// Real `uiServersProvider`, `serversProvider` chain and the real notifier;
/// only the repository and the network edge are fakes.
class _Rig {
  _Rig(this.servers) {
    for (final s in servers) {
      repo.entries.add(s);
    }
  }

  final List<ServerEntry> servers;
  final FakeServerRepository repo = FakeServerRepository();
  final FakeTester tester = FakeTester();
  final SettingsHarness base = SettingsHarness();
  final StreamController<List<ServerEntry>> list =
      StreamController<List<ServerEntry>>();

  List<dynamic> get overrides => [
    ...base.overrides,
    serverRepositoryProvider.overrideWithValue(repo),
    healthTesterProvider.overrideWithValue(tester),
    serversProvider.overrideWith((ref) => list.stream),
    networkProbeProvider.overrideWithValue(const OkProbe()),
  ];
}

Future<ProviderContainer> _pump(WidgetTester tester, _Rig rig) async {
  applyVariantView(tester, wide);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...rig.overrides.cast()],
      child: harnessApp(
        wide,
        ConsolarrEffectsScope(
          reduceMotion: true,
          child: const ConnectionCheckScreen(),
        ),
      ),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

void main() {
  late AppLocalizations l10n;
  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('loading, then data, then error: each state, never a stale '
      'list', (tester) async {
    final rig = _Rig([entry('a', name: 'Example A')]);
    addTearDown(rig.list.close);
    final c = await _pump(tester, rig);
    // Before the first frame is done the list is loading: skeleton.
    await tester.pump();
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.text(l10n.checkChooseServer), findsNothing);

    c.read(firstFrameDoneProvider.notifier).markDone();
    await tester.pump();
    expect(find.byType(SkeletonBox), findsWidgets, reason: 'stream pending');

    rig.list.add([entry('a', name: 'Example A')]);
    await tester.pumpAndSettle();
    expect(find.text('Example A'), findsOneWidget);

    // A reload that fails: Riverpod keeps the previous list as `value`, the
    // screen must show the error, not the old servers as current.
    rig.list.addError(StateError('read failed'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.checkLoadFailed), findsWidgets);
    expect(find.text('Example A'), findsNothing);
  });

  testWidgets('switching the chosen server drops the previous result and a '
      'late answer does not overwrite it', (tester) async {
    final a = entry('a', name: 'Example A');
    final b = entry('b', name: 'Example B');
    final rig = _Rig([a, b]);
    addTearDown(rig.list.close);
    final c = await _pump(tester, rig);
    c.read(firstFrameDoneProvider.notifier).markDone();
    rig.list.add([a, b]);
    await tester.pumpAndSettle();

    final notifier = c.read(connectionCheckProvider.notifier);
    rig.tester.gate = Completer<void>();
    notifier.select('a');
    final running = notifier.run();
    await tester.pump(const Duration(milliseconds: 10));
    expect(c.read(connectionCheckProvider).running, isTrue);

    // The user picks another server while the first check is still running.
    notifier.select('b');
    expect(c.read(connectionCheckProvider).serverId, 'b');
    expect(c.read(connectionCheckProvider).result, isNull);

    rig.tester.gate!.complete();
    await running;
    await tester.pumpAndSettle();
    final state = c.read(connectionCheckProvider);
    expect(state.serverId, 'b');
    expect(state.result, isNull, reason: 'the old server\'s result is dropped');
    expect(state.running, isFalse);
  });

  testWidgets('credentials are loaded for the chosen server only, not shown', (
    tester,
  ) async {
    final a = entry('a', name: 'Example A');
    final rig = _Rig([a]);
    addTearDown(rig.list.close);
    final c = await _pump(tester, rig);
    c.read(firstFrameDoneProvider.notifier).markDone();
    rig.list.add([a]);
    await tester.pumpAndSettle();
    final notifier = c.read(connectionCheckProvider.notifier);
    notifier.select('a');
    await notifier.run();
    await tester.pumpAndSettle();
    expect(rig.tester.profiles.single.id, 'a');
  });

  testWidgets('a server without its credentials fails the sign-in step with '
      'the API-key copy and sends no request', (tester) async {
    final a = entry('a', name: 'Example A', needsCredentials: true);
    final rig = _Rig([a]);
    addTearDown(rig.list.close);
    final c = await _pump(tester, rig);
    c.read(firstFrameDoneProvider.notifier).markDone();
    rig.list.add([a]);
    await tester.pumpAndSettle();
    final notifier = c.read(connectionCheckProvider.notifier);
    notifier.select('a');
    await notifier.run();
    await tester.pumpAndSettle();
    expect(rig.tester.profiles, isEmpty, reason: 'no request is sent');
    final result = c.read(connectionCheckProvider).result!;
    expect(result.finished, isTrue);
    expect(result.failed?.step, CheckStep.auth);
    expect(find.text(l10n.serverErrorApiKeyRequired), findsOneWidget);
    expect(c.read(connectionCheckProvider).running, isFalse);
  });
}
