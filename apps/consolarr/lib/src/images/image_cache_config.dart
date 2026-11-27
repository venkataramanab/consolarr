// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/painting.dart';

/// Upper bound for decoded images kept in memory (about 50 MB). The framework
/// default is 100 MB, which a poster grid can reach on a low-memory phone.
const int imageCacheMaxBytes = 50 * 1024 * 1024;

/// Entries (not bytes) kept at most; posters are small once decoded at display
/// size, so the byte cap is what normally binds.
const int imageCacheMaxEntries = 300;

/// Caps [cache]. Called after the first frame, never before: touching the
/// painting binding's cache earlier would be work before the first frame.
void configureImageCache(ImageCache cache) {
  cache
    ..maximumSizeBytes = imageCacheMaxBytes
    ..maximumSize = imageCacheMaxEntries;
}
