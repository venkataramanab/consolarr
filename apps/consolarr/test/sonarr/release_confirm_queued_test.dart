// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/release_search.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _target = InteractiveSearchTarget.episode(7);
const _hash = '0123456789abcdef0123456789abcdef01234567';

void main() {
  Future<bool> confirm(
    ArrRelease release,
    Result<List<ArrQueueItem>> queue,
  ) async {
    final api = ScriptedSonarrApi()
      ..grabResult = const Result.err(AppError(ErrorCategory.timeout))
      ..queueResult = queue;
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: sonarrTestOverrides(api),
    );
    addTearDown(c.dispose);
    c.listen(releaseGrabProvider(_target), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    final notifier = c.read(releaseGrabProvider(_target).notifier);
    await notifier.grab(release);
    expect(
      c.read(releaseGrabProvider(_target))[grabKey(release)],
      GrabStatus.maybeSent,
    );
    final found = await notifier.confirmQueued(release);
    expect(
      c.read(releaseGrabProvider(_target))[grabKey(release)],
      found ? GrabStatus.grabbed : GrabStatus.maybeSent,
    );
    return found;
  }

  test('the same title is found, ignoring case and outer space', () async {
    final release = fakeRelease(1, title: 'Example.Show.S01E01.GRP');
    final queue = Result.ok([
      fakeQueueItem(1, title: ' example.show.s01e01.grp '),
    ]);
    expect(await confirm(release, queue), isTrue);
  });

  test('the download id inside the release guid is found', () async {
    final release = fakeRelease(1, guid: 'magnet:?xt=urn:btih:$_hash');
    final queue = Result.ok([
      fakeQueueItem(1, title: 'Renamed By Client', downloadId: _hash),
    ]);
    expect(await confirm(release, queue), isTrue);
  });

  test('another title or download id is not found', () async {
    final release = fakeRelease(1, guid: 'guid-1');
    final queue = Result.ok([
      fakeQueueItem(1, title: 'Other.Show', downloadId: _hash),
      fakeQueueItem(2, title: 'Other.Show.2', downloadId: 'short'),
    ]);
    expect(await confirm(release, queue), isFalse);
  });

  test('an unreadable queue is never a match', () async {
    expect(
      await confirm(
        fakeRelease(1),
        const Result.err(AppError(ErrorCategory.timeout)),
      ),
      isFalse,
    );
  });
}
