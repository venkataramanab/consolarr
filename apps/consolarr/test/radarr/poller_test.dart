// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/radarr/presentation/poller.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lock extends Notifier<bool> {
  @override
  bool build() => false;

  void lock({required bool locked}) => state = locked;
}

final _lockProvider = NotifierProvider<_Lock, bool>(_Lock.new);

const _interval = Duration(seconds: 10);

class _Harness {
  int ticks = 0;
  Completer<void>? hold;
  final tabVisible = ValueNotifier<bool>(true);
  late final ProviderContainer container;

  Future<void> onTick() async {
    ticks++;
    final h = hold;
    if (h != null) await h.future;
  }

  Widget app({bool active = true}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: tabVisible,
        builder: (context, visible, _) => TickerMode(
          enabled: visible,
          child: Scaffold(
            body: VisiblePoller(
              active: active,
              interval: _interval,
              onTick: onTick,
              child: const Text('queue'),
            ),
          ),
        ),
      ),
    ),
  );
}

_Harness _harness() {
  final h = _Harness();
  h.container = ProviderContainer(
    overrides: [
      appLockedProvider.overrideWith((ref) => ref.watch(_lockProvider)),
    ],
  );
  addTearDown(h.container.dispose);
  addTearDown(h.tabVisible.dispose);
  return h;
}

void main() {
  testWidgets('ticks every interval while visible', (tester) async {
    final h = _harness();
    await tester.pumpWidget(h.app());
    await tester.pump(_interval);
    expect(h.ticks, 1);
    await tester.pump(_interval);
    expect(h.ticks, 2);
  });

  testWidgets('an inactive poller never ticks', (tester) async {
    final h = _harness();
    await tester.pumpWidget(h.app(active: false));
    await tester.pump(_interval * 3);
    expect(h.ticks, 0);
  });

  testWidgets('a tab that is not selected stops polling, and resumes', (
    tester,
  ) async {
    final h = _harness();
    await tester.pumpWidget(h.app());
    await tester.pump(_interval);
    expect(h.ticks, 1);

    h.tabVisible.value = false;
    await tester.pump();
    await tester.pump(_interval * 5);
    expect(h.ticks, 1, reason: 'no tick while another tab is selected');

    h.tabVisible.value = true;
    await tester.pump();
    // The timer starts again from the return: nothing fires at once, the
    // first tick is a full interval later.
    expect(h.ticks, 1);
    await tester.pump(_interval - const Duration(seconds: 1));
    expect(h.ticks, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(h.ticks, 2);
  });

  testWidgets('a route pushed on top pauses it; going back resumes it', (
    tester,
  ) async {
    final h = _harness();
    await tester.pumpWidget(h.app());
    await tester.pump(_interval);
    expect(h.ticks, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detail')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(_interval * 5);
    expect(h.ticks, 1, reason: 'no tick under a pushed route');

    navigator.pop();
    await tester.pumpAndSettle();
    expect(h.ticks, 1);
    await tester.pump(_interval);
    expect(h.ticks, 2);
  });

  testWidgets('ticks never overlap', (tester) async {
    final h = _harness();
    h.hold = Completer<void>();
    await tester.pumpWidget(h.app());
    await tester.pump(_interval);
    expect(h.ticks, 1);
    await tester.pump(_interval * 4);
    expect(h.ticks, 1, reason: 'the first tick has not finished');
    h.hold!.complete();
    h.hold = null;
    await tester.pump();
    await tester.pump(_interval);
    expect(h.ticks, 2);
  });

  testWidgets('it pauses while the app is locked and resumes after unlock', (
    tester,
  ) async {
    final h = _harness();
    await tester.pumpWidget(h.app());
    await tester.pump(_interval);
    expect(h.ticks, 1);

    h.container.read(_lockProvider.notifier).lock(locked: true);
    await tester.pump();
    await tester.pump(_interval * 5);
    expect(h.ticks, 1);

    h.container.read(_lockProvider.notifier).lock(locked: false);
    await tester.pump();
    await tester.pump(_interval);
    expect(h.ticks, 2);
  });

  testWidgets('it pauses in the background and resumes in front', (
    tester,
  ) async {
    final h = _harness();
    await tester.pumpWidget(h.app());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(_interval * 3);
    expect(h.ticks, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_interval);
    expect(h.ticks, 1);
  });

  testWidgets('disposing the poller cancels the timer', (tester) async {
    final h = _harness();
    await tester.pumpWidget(h.app());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: Text('other')),
      ),
    );
    await tester.pump(_interval * 3);
    expect(h.ticks, 0);
  });
}
