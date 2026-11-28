// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Holds a [ReceivePort]: it cannot be sent to another isolate, exactly like
/// a client that owns a Dio / HttpClient.
class _Unsendable {
  final port = ReceivePort();

  int instanceParse(String body) => body.length + port.hashCode * 0;
}

int _length(String body) => body.length;

class _Static {
  static int count(String body) => body.length;
}

void main() {
  final big = 'x' * (isolateThresholdBytes + 1);

  test('threshold is 64 KB', () {
    expect(isolateThresholdBytes, 64 * 1024);
  });

  test('a small body is parsed inline, the runner is not used', () async {
    var used = false;
    Future<T> spy<T>(T Function() c) {
      used = true;
      return Future.value(c());
    }

    expect(await parseOffIsolate(spy, 'abc', _length), 3);
    expect(used, isFalse);
  });

  test('a large body goes through the runner', () async {
    var used = false;
    Future<T> spy<T>(T Function() c) {
      used = true;
      return Future.value(c());
    }

    expect(await parseOffIsolate(spy, big, _length), big.length);
    expect(used, isTrue);
  });

  test('a real isolate parses a large body next to an unsendable holder '
      '(top-level and static parsers)', () async {
    final holder = _Unsendable();
    addTearDown(holder.port.close);
    expect(await parseOffIsolate(isolateRunner, big, _length), big.length);
    expect(
      await parseOffIsolate(isolateRunner, big, _Static.count),
      big.length,
    );
    // The holder is still alive and untouched.
    expect(holder.port.hashCode, isNotNull);
  });

  test('capturing the unsendable holder (an instance tear-off) is rejected '
      'by the real isolate, never silently accepted', () async {
    final holder = _Unsendable();
    addTearDown(holder.port.close);
    await expectLater(
      parseOffIsolate(isolateRunner, big, holder.instanceParse),
      throwsA(anything),
    );
  });

  test('the helper is top level, captures no `this` and imports only '
      'dart:isolate', () {
    final src = File('lib/src/off_isolate.dart').readAsStringSync();
    expect(src, contains('\nFuture<T> parseOffIsolate<T>('));
    expect(src, isNot(contains('this.')));
    final imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(src).map((m) => m.group(1)).toList();
    expect(imports, ['dart:isolate']);
  });
}
