// SPDX-License-Identifier: GPL-3.0-or-later

// Guards the hardened Android configuration of both apps.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

/// The packages that list `cross_file` as a dependency, from
/// `dart pub deps --json` run in [root] (the resolved graph, not a guess).
List<String> crossFileDependents(String root) {
  final result = Process.runSync(
    Platform.resolvedExecutable.endsWith('dart')
        ? Platform.resolvedExecutable
        : 'dart',
    ['pub', 'deps', '--json'],
    workingDirectory: root,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  return [
    for (final p in json['packages'] as List<dynamic>)
      if (((p as Map<String, dynamic>)['dependencies'] as List<dynamic>)
          .contains('cross_file'))
        p['name']! as String,
  ];
}

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
          // Every exclude names a path so it cannot be read as a no-op.
          final excludes = RegExp(r'<exclude [^>]*>').allMatches(xml);
          expect(excludes, isNotEmpty);
          for (final e in excludes) {
            expect(e.group(0), contains('path="."'));
          }
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

      test('only INTERNET and the opt-in app lock biometric are requested', () {
        final permissions = RegExp(
          r'<uses-permission[^>]*android:name="([^"]+)"',
        ).allMatches(manifest).map((m) => m.group(1)).toList();
        expect(permissions, [
          'android.permission.INTERNET',
          'android.permission.USE_BIOMETRIC',
        ]);
      });

      test('the only added query is an https view intent (browser launch)', () {
        final queries = RegExp(
          r'<queries>.*?</queries>',
          dotAll: true,
        ).firstMatch(manifest)!.group(0)!;
        expect(queries, contains('android.intent.action.VIEW'));
        expect(queries, contains('android:scheme="https"'));
        expect(queries, isNot(contains('android:scheme="http"')));
        expect(queries, isNot(contains('<package')));
      });

      test('the activity is a FragmentActivity (platform authenticator) and '
          'adds no exported component', () {
        final kotlin = read(
          '$root/android/app/src/main/kotlin/org/consolarr/app/MainActivity.kt',
        );
        expect(kotlin, contains('FlutterFragmentActivity'));
        expect(manifest, isNot(contains('<provider')));
        expect('android:exported="true"'.allMatches(manifest), hasLength(1));
      });

      test('sharing is a first-party text intent: no share_plus, no file '
          'provider', () {
        final kotlin = read(
          '$root/android/app/src/main/kotlin/org/consolarr/app/MainActivity.kt',
        );
        expect(kotlin, contains('"consolarr/share"'));
        expect(kotlin, contains('Intent.ACTION_SEND'));
        expect(kotlin, contains('Intent.EXTRA_TEXT'));
        expect(kotlin, contains('Intent.createChooser'));
        // Text only: no stream, no URI grant.
        expect(kotlin, isNot(contains('EXTRA_STREAM')));
        expect(kotlin, isNot(contains('FLAG_GRANT_READ_URI_PERMISSION')));
        expect(manifest, isNot(contains('<provider')));
        expect(read('$root/pubspec.yaml'), isNot(contains('share_plus')));
        final lock = read(
          '${Directory.current.parent.parent.path}/pubspec.lock',
        );
        expect(lock, isNot(contains('share_plus')));
        // `cross_file` came with share_plus. It may stay only while it is a
        // transitive dependency of the `file_selector` packages (the torrent
        // file picker), never as a direct one, and only for as long as one of
        // them actually depends on it (`dart pub deps --json` says so): the
        // allowance expires with the dependency.
        expect(read('$root/pubspec.yaml'), isNot(contains('cross_file')));
        final entry = RegExp(
          r'^  cross_file:\n((?:    .*\n)+)',
          multiLine: true,
        ).firstMatch(lock);
        if (entry != null) {
          expect(entry.group(1), contains('dependency: transitive'));
          final dependents = crossFileDependents(root);
          expect(
            dependents,
            isNotEmpty,
            reason: 'cross_file is locked but nothing depends on it',
          );
          expect(
            dependents.where((n) => !n.startsWith('file_selector')),
            isEmpty,
            reason: 'only file_selector packages may bring in cross_file',
          );
        }
      });

      test('only the English and Arabic resources are packaged', () {
        expect(gradle, contains('localeFilters'));
        expect(gradle, contains('"en"'));
        expect(gradle, contains('"ar"'));
      });

      test('only the launcher activity is exported', () {
        expect('android:exported="true"'.allMatches(manifest), hasLength(1));
      });

      test('library receivers that are exported by default are removed', () {
        expect(
          manifest,
          contains('androidx.profileinstaller.ProfileInstallReceiver'),
        );
        expect(manifest, contains('tools:node="remove"'));
      });

      test('minSdk 26, placeholder application id, R8 and shrinking on', () {
        expect(gradle, contains('minSdk = 26'));
        expect(gradle, contains('applicationId = "org.consolarr.app"'));
        expect(gradle, contains('isMinifyEnabled = true'));
        expect(gradle, contains('isShrinkResources = true'));
      });

      test('release without key.properties fails unless debug signing is '
          'explicitly allowed', () {
        expect(gradle, contains('hasReleaseKeystore'));
        expect(gradle, contains('consolarr.allowDebugSigning'));
        expect(gradle, contains('throw GradleException'));
        expect(gradle, contains('assembleRelease'));
      });

      test('gradle wrapper distribution is checksum-pinned', () {
        final props = read(
          '$root/android/gradle/wrapper/gradle-wrapper.properties',
        );
        expect(props, matches(RegExp(r'distributionSha256Sum=[0-9a-f]{64}')));
      });

      test('application id suffix distinguishes the Play build', () {
        if (name == 'consolarr_play') {
          expect(gradle, contains('applicationIdSuffix = ".play"'));
        } else {
          expect(gradle, isNot(contains('applicationIdSuffix')));
        }
      });
    });
  });
}
