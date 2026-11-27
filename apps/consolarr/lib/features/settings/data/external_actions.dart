// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The most text handed to the system share sheet, in UTF-8 bytes. The text
/// travels in the chooser intent as UTF-16 (up to twice this size when it is
/// ASCII), and Binder transactions share a buffer of about 1 MB for the whole
/// process, so the cap stays far below that.
const int shareTextMaxBytes = 150 * 1024;

/// The part at the start of a long text that is always kept (the bundle
/// header and section titles), in UTF-8 bytes.
const int _shareHeadMaxBytes = 4 * 1024;

bool _isContinuation(int byte) => (byte & 0xC0) == 0x80;

/// [text] cut to at most [maxBytes] UTF-8 bytes, always on a character
/// boundary. When it is cut, the start of the text and its newest end (whole
/// lines where possible) are kept, with [note] between them. The result, note
/// included, stays within [maxBytes].
({String text, bool truncated}) capShareText(
  String text,
  String note, {
  int maxBytes = shareTextMaxBytes,
}) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return (text: text, truncated: false);
  final separator = utf8.encode('\n\n$note\n\n');
  final budget = math.max(0, maxBytes - separator.length);

  var headEnd = math.min(_shareHeadMaxBytes, budget ~/ 4);
  while (headEnd > 0 && _isContinuation(bytes[headEnd])) {
    headEnd--;
  }
  final headNewline = bytes.lastIndexOf(10, math.max(0, headEnd - 1));
  if (headNewline > 0 && headNewline < headEnd) headEnd = headNewline;

  var tailStart = math.min(bytes.length, bytes.length - (budget - headEnd));
  while (tailStart < bytes.length && _isContinuation(bytes[tailStart])) {
    tailStart++;
  }
  final lineStart = bytes.indexOf(10, tailStart);
  if (lineStart != -1 && lineStart + 1 < bytes.length) {
    tailStart = lineStart + 1;
  }
  final out = BytesBuilder(copy: false)
    ..add(bytes.sublist(0, headEnd))
    ..add(separator)
    ..add(bytes.sublist(tailStart));
  return (text: utf8.decode(out.takeBytes()), truncated: true);
}

/// Things the app asks the system to do on an explicit tap: open an address in
/// the browser, show the share sheet, read the platform version. The app
/// itself makes no request.
abstract interface class ExternalActions {
  /// Opens an `https` address in the browser. Returns whether it opened.
  Future<bool> openHttps(Uri uri);

  /// Shares [text] as plain text through the system share sheet. Text over
  /// [shareTextMaxBytes] is cut (newest end kept) and [truncationNote] added. Returns whether
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
