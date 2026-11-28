// SPDX-License-Identifier: GPL-3.0-or-later

// Notifications and background execution are deferred: nothing of them ships.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final roots = [
    Directory.current.path,
    '${Directory.current.parent.path}/consolarr_play',
  ];
  final lock = File('${Directory.current.parent.parent.path}/pubspec.lock')
      .readAsStringSync();

  test('no background or notification dependency, direct or locked', () {
    const banned = [
      'workmanager',
      'flutter_local_notifications',
      'awesome_notifications',
      'firebase_messaging',
      'flutter_background_service',
      'android_alarm_manager',
      'background_fetch',
      'permission_handler',
    ];
    for (final root in roots) {
      final pubspec = File('$root/pubspec.yaml').readAsStringSync();
      for (final name in banned) {
        expect(pubspec, isNot(contains(name)), reason: '$root $name');
      }
    }
    for (final name in banned) {
      expect(lock, isNot(contains('\n  $name:')), reason: name);
    }
  });

  test('the manifests add no notification, wake, boot or service entry', () {
    for (final root in roots) {
      final dir = Directory('$root/android/app/src');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('AndroidManifest.xml')) continue;
        final xml = f.readAsStringSync();
        for (final banned in [
          'POST_NOTIFICATIONS',
          'WAKE_LOCK',
          'RECEIVE_BOOT_COMPLETED',
          'FOREGROUND_SERVICE',
        ]) {
          expect(xml, isNot(contains(banned)), reason: '${f.path} $banned');
        }
        // A service or receiver may only appear to be removed.
        for (final m in RegExp(
          r'<(service|receiver)\b[^>]*>',
        ).allMatches(xml)) {
          expect(m.group(0), contains('tools:node="remove"'), reason: f.path);
        }
      }
    }
  });

  test('the polling layer declares no provider (nothing starts at launch)', () {
    final dir = Directory('lib/shared/polling');
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      expect(src, isNot(contains('Provider<')), reason: f.path);
      expect(src, isNot(contains('NotifierProvider')), reason: f.path);
    }
  });
}
