// SPDX-License-Identifier: GPL-3.0-or-later

// The helper lives in `core` (one copy for every client package); these names
// stay for existing call sites.
export 'package:core/core.dart'
    show
        ParseRunner,
        isolateRunner,
        isolateThresholdBytes,
        parseOffIsolate;
