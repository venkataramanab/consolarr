// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/release_search.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'support.dart';

const _target = InteractiveSearchTarget.episode(7);

ResponseBody _ok() => ResponseBody.fromString(
  '{}',
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  final release = fakeRelease(1);

  ProviderContainer containerOver(FaultInjectingAdapter adapter) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sonarrSessionProvider.overrideWith(
          (ref) => SonarrSession(
            api: SonarrClient(dio: fakeConnection(adapter).dio),
            serverId: 'srv1',
            cache: MemoryPayloadCache(),
            clock: DateTime.now,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(releaseGrabProvider(_target), (_, _) {});
    return c;
  }

  Future<GrabStatus?> grab(ProviderContainer c) async {
    await c.read(sonarrSessionProvider.future);
    await c.read(releaseGrabProvider(_target).notifier).grab(release);
    return c.read(releaseGrabProvider(_target))[grabKey(release)];
  }

  test(
    'a dropped connection mid-grab is "maybe sent" and never re-sent',
    () async {
      final adapter = FaultInjectingAdapter(
        inner: StubAdapter((_) => _ok()),
        faults: const [ConnectionDropFault()],
      );
      final c = containerOver(adapter);
      expect(await grab(c), GrabStatus.maybeSent);
      expect(adapter.requestCount, 1);
      // Nothing happens on its own; only an explicit tap sends again.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(adapter.requestCount, 1);
    },
  );

  test(
    'a timeout is "maybe sent"; a plain second grab sends nothing',
    () async {
      final adapter = FaultInjectingAdapter(
        inner: StubAdapter((_) => _ok()),
        faults: const [
          TimeoutFault(kind: TimeoutKind.receive, firstAttempts: 1),
        ],
      );
      final c = containerOver(adapter);
      expect(await grab(c), GrabStatus.maybeSent);
      // No queue check and no confirmation yet: nothing may be sent.
      expect(await grab(c), GrabStatus.maybeSent);
      expect(adapter.requestCount, 1);
    },
  );

  test(
    'after a confirmed resend a maybe-sent release is sent once more',
    () async {
      final adapter = FaultInjectingAdapter(
        inner: StubAdapter((_) => _ok()),
        faults: const [
          TimeoutFault(kind: TimeoutKind.receive, firstAttempts: 1),
        ],
      );
      final c = containerOver(adapter);
      expect(await grab(c), GrabStatus.maybeSent);
      await c
          .read(releaseGrabProvider(_target).notifier)
          .grab(release, confirmedResend: true);
      expect(
        c.read(releaseGrabProvider(_target))[grabKey(release)],
        GrabStatus.grabbed,
      );
      expect(adapter.requestCount, 2);
    },
  );

  test('a grabbed release cannot be grabbed twice', () async {
    final adapter = FaultInjectingAdapter(inner: StubAdapter((_) => _ok()));
    final c = containerOver(adapter);
    expect(await grab(c), GrabStatus.grabbed);
    await grab(c);
    expect(adapter.requestCount, 1);
  });

  test('concurrent taps while grabbing send one request', () async {
    final adapter = FaultInjectingAdapter(
      inner: StubAdapter((_) => _ok()),
      faults: const [LatencyFault(Duration(milliseconds: 30))],
    );
    final c = containerOver(adapter);
    await c.read(sonarrSessionProvider.future);
    final notifier = c.read(releaseGrabProvider(_target).notifier);
    await Future.wait([notifier.grab(release), notifier.grab(release)]);
    expect(adapter.requestCount, 1);
  });

  test('5xx and 401 are definite failures', () async {
    for (final code in [500, 401]) {
      final adapter = FaultInjectingAdapter(
        inner: StubAdapter((_) => ResponseBody.fromString('', code)),
      );
      final c = containerOver(adapter);
      expect(await grab(c), GrabStatus.failed, reason: '$code');
    }
  });

  test('the request carries the guid and indexer, not the title', () async {
    late RequestOptions seen;
    final adapter = FaultInjectingAdapter(
      inner: StubAdapter((o) {
        seen = o;
        return _ok();
      }),
    );
    await grab(containerOver(adapter));
    expect(seen.method, 'POST');
    expect(seen.uri.path, endsWith('/api/v3/release'));
    expect(seen.uri.query, isEmpty);
    expect(seen.data, contains('guid-1'));
    expect(seen.data, isNot(contains(release.title)));
  });
}
