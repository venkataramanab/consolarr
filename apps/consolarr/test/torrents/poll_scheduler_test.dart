// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/poll_scheduler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pollDelay', () {
    test('doubles with every failure and stops at the cap', () {
      const base = Duration(seconds: 3);
      expect(pollDelay(base, 0), base);
      expect(pollDelay(base, 1), const Duration(seconds: 6));
      expect(pollDelay(base, 2), const Duration(seconds: 12));
      expect(pollDelay(base, 3), const Duration(seconds: 24));
      expect(pollDelay(base, 4), const Duration(seconds: 48));
      expect(pollDelay(base, 5), maxPollBackoff);
      expect(pollDelay(base, 50), maxPollBackoff);
    });

    test('a base above the cap is never shortened', () {
      expect(
        pollDelay(const Duration(seconds: 120), 3),
        const Duration(seconds: 120),
      );
    });
  });

  group('PollScheduler timeline (fake time)', () {
    test('success keeps the interval; failures back off; success resets', () {
      fakeAsync((async) {
        final results = <bool>[false, false, false, true];
        final fired = <int>[];
        final scheduler = PollScheduler(
          interval: const Duration(seconds: 3),
          isVisible: () => true,
          tick: () async {
            fired.add(async.elapsed.inSeconds);
            return results.isEmpty ? true : results.removeAt(0);
          },
        )..start();
        async.elapse(const Duration(seconds: 200));
        // 3 (fail) -> +6 (fail) -> +12 (fail) -> +24 (ok) -> then every 3 s.
        expect(fired.take(5).toList(), [3, 9, 21, 45, 48]);
        scheduler.dispose();
      });
    });

    test('nothing runs while hidden, and polling resumes when visible', () {
      fakeAsync((async) {
        var visible = false;
        var ticks = 0;
        final scheduler = PollScheduler(
          interval: const Duration(seconds: 2),
          isVisible: () => visible,
          tick: () async {
            ticks++;
            return true;
          },
        )..start();
        async.elapse(const Duration(seconds: 60));
        expect(ticks, 0);
        visible = true;
        async.elapse(const Duration(seconds: 4));
        expect(ticks, greaterThan(0));
        scheduler.dispose();
      });
    });

    test('dispose stops the timer; a new interval restarts the wait', () {
      fakeAsync((async) {
        var ticks = 0;
        final scheduler = PollScheduler(
          interval: const Duration(seconds: 10),
          isVisible: () => true,
          tick: () async {
            ticks++;
            return true;
          },
        )..start();
        async.elapse(const Duration(seconds: 5));
        scheduler.setInterval(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 3));
        expect(ticks, 3);
        scheduler.dispose();
        async.elapse(const Duration(minutes: 5));
        expect(ticks, 3);
      });
    });

    test('a tick never overlaps the previous one', () {
      fakeAsync((async) {
        var running = 0;
        var maxRunning = 0;
        final scheduler = PollScheduler(
          interval: const Duration(seconds: 1),
          isVisible: () => true,
          tick: () async {
            running++;
            if (running > maxRunning) maxRunning = running;
            await Future<void>.delayed(const Duration(seconds: 5));
            running--;
            return true;
          },
        )..start();
        async.elapse(const Duration(seconds: 30));
        expect(maxRunning, 1);
        scheduler.dispose();
      });
    });
  });
}
