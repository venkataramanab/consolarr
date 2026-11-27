// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:security/security.dart';

/// Whether [bytes] start like a JPEG, PNG, WebP or GIF image.
///
/// Server-supplied images are untrusted: anything else (HTML error pages,
/// SVG, other formats) is refused before it reaches the decoder.
bool looksLikeSupportedImage(Uint8List bytes) {
  bool at(int offset, List<int> magic) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  return at(0, const [0xFF, 0xD8, 0xFF]) ||
      at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ||
      at(0, const [0x47, 0x49, 0x46, 0x38]) ||
      (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
          at(8, const [0x57, 0x45, 0x42, 0x50]));
}

/// An image loaded through the server's secure [Dio].
///
/// The client comes from `SecureHttpClientFactory`, so images obey the same
/// TLS pinning, cleartext and redirect rules as API calls, and the API key is
/// already in the client's headers: it is never part of [uri].
///
/// Wrap in `ResizeImage` (or pass the `cacheWidth` of `PosterCard`) so the
/// image is decoded at display size, not full size.
class SecureNetworkImage extends ImageProvider<SecureNetworkImage> {
  const SecureNetworkImage({
    required this.dio,
    required this.uri,
    this.maxBytes = defaultMaxBytes,
  });

  /// Largest accepted artwork download (8 MiB).
  static const defaultMaxBytes = 8 * 1024 * 1024;

  final Dio dio;
  final Uri uri;
  final int maxBytes;

  @override
  Future<SecureNetworkImage> obtainKey(ImageConfiguration configuration) =>
      Future<SecureNetworkImage>.value(this);

  @override
  ImageStreamCompleter loadImage(
    SecureNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1,
      debugLabel: 'SecureNetworkImage',
    );
  }

  Future<ui.Codec> _load(
    SecureNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    final response = await key.dio.getUri<List<int>>(
      key.uri,
      options: Options(
        responseType: ResponseType.bytes,
        extra: {maxResponseBytesKey: key.maxBytes},
      ),
    );
    final data = response.data;
    final bytes = data == null ? Uint8List(0) : Uint8List.fromList(data);
    if (!looksLikeSupportedImage(bytes)) {
      throw const FormatException('not a supported image');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is SecureNetworkImage &&
      identical(other.dio, dio) &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(identityHashCode(dio), uri);

  /// Omits the URI (it contains the media id and path prefix).
  @override
  String toString() => 'SecureNetworkImage()';
}
