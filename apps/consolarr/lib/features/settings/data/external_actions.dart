// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The most text handed to the system share sheet, in UTF-8 bytes. Intents
/// travel through the Binder, whose transaction buffer is about 1 MB for the
/// whole process, so the text is capped well below that.
const int shareTextMaxBytes = 500 * 1024;

/// [text] cut to at most [maxBytes] UTF-8 bytes (on a character boundary),
/// with [note] appended on its own line when it was cut. The result,
/// note included, stays within [maxBytes].
({String text, bool truncated}) capShareText(
  String text,
  String note, {
  int maxBytes = shareTextMaxBytes,
}) {
  if (utf8.encode(text).length <= maxBytes) {
    return (text: text, truncated: false);
  }
  final suffix = '\n\n$note';
  final budget = maxBytes - utf8.encode(suffix).length;
  final kept = StringBuffer();
  var used = 0;
  for (final rune in text.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (used + size > budget) break;
    used += size;
    kept.writeCharCode(rune);
  }
  return (text: '$kept$suffix', truncated: true);
}

/// Things the app asks the system to do on an explicit tap: open an address in
/// the browser, show the share sheet, read the platform version. The app
/// itself makes no request.
abstract interface class ExternalActions {
  /// Opens an `https` address in the browser. Returns whether it opened.
  Future<bool> openHttps(Uri uri);

  /// Shares [text] as plain text through the system share sheet. Text over
  /// [shareTextMaxBytes] is cut and [truncationNote] appended. Returns whether
  /// it was cut. Throws when the share sheet cannot be shown.
  Future<bool> shareText({
    required String text,
    required String subject,
    required String truncationNote,
  });

  /// For example `Android API 34`, or `unknown`.
  Future<String> platformDescription();
}

/// The Android implementation.
class PlatformExternalActions implements ExternalActions {
  const PlatformExternalActions();

  static const _channel = MethodChannel('consolarr/platform_info');
  static const _shareChannel = MethodChannel('consolarr/share');

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
  Future<bool> shareText({
    required String text,
    required String subject,
    required String truncationNote,
  }) async {
    final capped = capShareText(text, truncationNote);
    await _shareChannel.invokeMethod<void>('shareText', {
      'text': capped.text,
      'subject': subject,
    });
    return capped.truncated;
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
  final List<String> shared = [];
  bool openResult = true;

  @override
  Future<bool> openHttps(Uri uri) async {
    if (uri.scheme != 'https') return false;
    opened.add(uri);
    return openResult;
  }

  @override
  Future<bool> shareText({
    required String text,
    required String subject,
    required String truncationNote,
  }) async {
    final capped = capShareText(text, truncationNote);
    shared.add(capped.text);
    return capped.truncated;
  }

  @override
  Future<String> platformDescription() async => 'Android API 34';
}
