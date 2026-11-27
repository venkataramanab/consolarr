// SPDX-License-Identifier: GPL-3.0-or-later

// Guards the hardened Android configuration of both apps.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  final apps = {
    'consolarr': Directory.current.path,
    'consolarr_play': '${Directory.current.parent.path}/consolarr_play',
  };

  apps.forEach((name, root) {
    group(name, () {
      final manifest = read('$root/android/app/src/main/AndroidManifest.xml');
      final gradle = read('$root/android/app/build.gradle.kts');

      test('backups are disabled and extraction rules exclude everything', () {
        expect(manifest, contains('android:allowBackup="false"'));
        expect(manifest, contains('android:dataExtractionRules='));
        expect(manifest, contains('android:fullBackupContent='));
        for (final file in ['data_extraction_rules.xml', 'backup_rules.xml']) {
          final xml = read('$root/android/app/src/main/res/xml/$file');
          expect(xml, contains('<exclude domain="root"'));
          expect(xml, contains('<exclude domain="sharedpref"'));
          expect(xml, contains('<exclude domain="database"'));
          expect(xml, isNot(contains('<include')));
        }
      });

      test('platform cleartext is denied by default', () {
        expect(manifest, contains('android:usesCleartextTraffic="false"'));
        final nsc = read(
          '$root/android/app/src/main/res/xml/network_security_config.xml',
        );
        expect(nsc, contains('cleartextTrafficPermitted="false"'));
        expect(nsc, isNot(contains('src="user"')));
      });

      test('only the INTERNET permission is requested', () {
        final permissions = RegExp(
          r'<uses-permission[^>]*android:name="([^"]+)"',
        ).allMatches(manifest).map((m) => m.group(1)).toList();
        expect(permissions, ['android.permission.INTERNET']);
      });

      test('only the launcher activity is exported', () {
        expect('android:exported="true"'.allMatches(manifest), hasLength(1));
      });

      test('minSdk 26, placeholder application id, R8 and shrinking on', () {
        expect(gradle, contains('minSdk = 26'));
        expect(gradle, contains('applicationId = "org.consolarr.app"'));
        expect(gradle, contains('isMinifyEnabled = true'));
        expect(gradle, contains('isShrinkResources = true'));
      });

      test(
        'release falls back to the debug key when key.properties is absent',
        () {
          expect(gradle, contains('hasReleaseKeystore'));
          expect(gradle, contains('signingConfigs.getByName("debug")'));
        },
      );
    });
  });
}
