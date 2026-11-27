// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Things the app asks the system to do on an explicit tap: open an address in
/// the browser, show the share sheet, read the platform version. The app
/// itself makes no request.
abstract interface class ExternalActions {
  /// Opens an `https` address in the browser. Returns whether it opened.
  Future<bool> openHttps(Uri uri);

  /// Shares [bytes] as a file named [fileName] through the system share sheet.
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required String subject,
  });

  /// For example `Android API 34`, or `unknown`.
  Future<String> platformDescription();
}

/// The Android implementation.
class PlatformExternalActions implements ExternalActions {
  const PlatformExternalActions();

  static const _channel = MethodChannel('consolarr/platform_info');

  @override
  Future<bool> openHttps(Uri uri) async {
    if (uri.scheme != 'https') return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required String subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        fileNameOverrides: [fileName],
        subject: subject,
      ),
    );
  }

  @override
  Future<String> platformDescription() async {
    try {
      final api = await _channel.invokeMethod<int>('apiLevel');
      return api == null ? 'unknown' : 'Android API $api';
    } on Object {
      return 'unknown';
    }
  }
}

/// Records calls; tests.
class RecordingExternalActions implements ExternalActions {
  final List<Uri> opened = [];
  final List<({String fileName, Uint8List bytes})> shared = [];
  bool openResult = true;

  @override
  Future<bool> openHttps(Uri uri) async {
    if (uri.scheme != 'https') return false;
    opened.add(uri);
    return openResult;
  }

  @override
  Future<void> shareFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required String subject,
  }) async => shared.add((fileName: fileName, bytes: bytes));

  @override
  Future<String> platformDescription() async => 'Android API 34';
}
