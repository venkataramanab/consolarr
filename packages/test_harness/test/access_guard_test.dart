// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

class _Quiet extends StatelessWidget {
  const _Quiet();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _Network extends StatelessWidget {
  const _Network();
  @override
  Widget build(BuildContext context) {
    HttpClient().close(force: true);
    return const SizedBox();
  }
}

class _Database extends StatelessWidget {
  const _Database();
  @override
  Widget build(BuildContext context) {
    File('/tmp/consolarr-test/library.sqlite3');
    return const SizedBox();
  }
}

class _ReportsDatabase extends StatelessWidget {
  const _ReportsDatabase(this.recorder);
  final AccessRecorder recorder;
  @override
  Widget build(BuildContext context) {
    recorder.recordDatabase('open');
    return const SizedBox();
  }
}

void main() {
  testWidgets('passes when nothing touches I/O before the first frame', (
    tester,
  ) async {
    await expectNoIoBeforeFirstFrame(tester, const _Quiet());
  });

  testWidgets('fails on network use before the first frame', (tester) async {
    await expectTestFailure(
      () => expectNoIoBeforeFirstFrame(tester, const _Network()),
      message: contains('network: HttpClient created'),
    );
  });

  testWidgets('fails on file-backed database access', (tester) async {
    await expectTestFailure(
      () => expectNoIoBeforeFirstFrame(tester, const _Database()),
      message: contains('database: file /tmp/consolarr-test/library.sqlite3'),
    );
  });

  testWidgets('fails when a fake database layer reports access', (
    tester,
  ) async {
    final recorder = AccessRecorder();
    await expectTestFailure(
      () => expectNoIoBeforeFirstFrame(
        tester,
        _ReportsDatabase(recorder),
        recorder: recorder,
      ),
      message: contains('database: open'),
    );
  });

  testWidgets('restores global overrides afterwards', (tester) async {
    final before = HttpOverrides.current;
    await expectNoIoBeforeFirstFrame(tester, const _Quiet());
    expect(HttpOverrides.current, same(before));
  });
}
