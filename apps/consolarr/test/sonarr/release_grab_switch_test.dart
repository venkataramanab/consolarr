// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/sonarr/application/release_search.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _target = InteractiveSearchTarget.episode(7);

void main() {
  test('a grab started on server A never shows against server B', () async {
    final gate = Completer<void>();
    final first = ScriptedSonarrApi()
      ..hook = (n) => n == 'grabRelease' ? gate.future : Future.value();
    final second = ScriptedSonarrApi();
    final servers = SwitchableSonarr(first, second);
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: servers.overrides,
    );
    addTearDown(c.dispose);
    c.listen(releaseGrabProvider(_target), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    final release = fakeRelease(1);
    final grab = c.read(releaseGrabProvider(_target).notifier).grab(release);
    await Future<void>.delayed(Duration.zero);
    expect(
      c.read(releaseGrabProvider(_target))[grabKey(release)],
      GrabStatus.grabbing,
    );
    servers.switchToSecond(c);
    await c.read(sonarrSessionProvider.future);
    // Server B starts clean: nothing is "grabbing" for its same-numbered item.
    expect(c.read(releaseGrabProvider(_target)), isEmpty);
    gate.complete();
    await grab;
    expect(c.read(releaseGrabProvider(_target)), isEmpty);
    expect(second.count('grabRelease'), 0);
  });

  test(
    'the queue check of a maybe-sent release ignores a server switch',
    () async {
      final first = ScriptedSonarrApi()
        ..grabResult = const Result.err(AppError(ErrorCategory.timeout));
      final second = ScriptedSonarrApi();
      final servers = SwitchableSonarr(first, second);
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: servers.overrides,
      );
      addTearDown(c.dispose);
      c.listen(releaseGrabProvider(_target), (_, _) {});
      await c.read(sonarrSessionProvider.future);
      final release = fakeRelease(1);
      final notifier = c.read(releaseGrabProvider(_target).notifier);
      await notifier.grab(release);
      expect(
        c.read(releaseGrabProvider(_target))[grabKey(release)],
        GrabStatus.maybeSent,
      );
      servers.switchToSecond(c);
      await c.read(sonarrSessionProvider.future);
      expect(await notifier.confirmQueued(release), isFalse);
      expect(second.count('queue'), 0);
    },
  );
}
