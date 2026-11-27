// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records network and database access attempts made while a guard is active.
///
/// Database layers cannot be intercepted generically, so fakes and thin
/// wrappers report through [recordDatabase]. File-backed databases are also
/// detected by file name (see [AccessRecorder.looksLikeDatabase]).
///
/// Limits (this is a tripwire for accidental eager work, not a sandbox):
///  * only `HttpClient`s created through `HttpOverrides` while the guard is
///    active are seen. Clients created earlier, in other isolates, raw
///    `Socket`/`RawSocket`/`WebSocket` use, platform channels and FFI are not;
///  * database access is detected by file name or explicit reports only;
///  * it covers the first `pumpWidget` only, not work scheduled afterwards.
/// The guard observes and never changes certificate validation, which is why
/// it is the one place outside `package:security` allowed to name
/// `HttpOverrides`.
class AccessRecorder {
  final List<String> events = [];

  void recordNetwork(String detail) => events.add('network: $detail');
  void recordDatabase(String detail) => events.add('database: $detail');

  static final _dbPath = RegExp(
    r'\.(db|sqlite3?|sqlite-wal|sqlite-shm|isar|hive|realm)$|-(wal|shm|journal)$',
    caseSensitive: false,
  );

  static bool looksLikeDatabase(String path) => _dbPath.hasMatch(path);
}

base class _RecordingHttpOverrides extends HttpOverrides {
  _RecordingHttpOverrides(this.recorder);
  final AccessRecorder recorder;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    recorder.recordNetwork('HttpClient created');
    return super.createHttpClient(context);
  }
}

base class _RecordingIoOverrides extends IOOverrides {
  _RecordingIoOverrides(this.recorder);
  final AccessRecorder recorder;

  @override
  File createFile(String path) {
    if (AccessRecorder.looksLikeDatabase(path)) {
      recorder.recordDatabase('file $path');
    }
    return super.createFile(path);
  }
}

/// Pumps [app] and fails if anything touched the network or a database
/// before the first frame was produced (the app must do no work before the
/// first frame; everything is initialised lazily).
Future<void> expectNoIoBeforeFirstFrame(
  WidgetTester tester,
  Widget app, {
  AccessRecorder? recorder,
}) async {
  final rec = recorder ?? AccessRecorder();
  final previousHttp = HttpOverrides.current;
  final previousIo = IOOverrides.current;
  HttpOverrides.global = _RecordingHttpOverrides(rec);
  IOOverrides.global = _RecordingIoOverrides(rec);
  try {
    await tester.pumpWidget(app);
  } finally {
    HttpOverrides.global = previousHttp;
    IOOverrides.global = previousIo;
  }
  if (rec.events.isNotEmpty) {
    fail(
      'I/O before first frame:\n  ${rec.events.join('\n  ')}\n'
      'Defer network and database work until after the first frame.',
    );
  }
}
