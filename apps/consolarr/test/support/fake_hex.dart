// SPDX-License-Identifier: GPL-3.0-or-later

// Hex-shaped test values (info hashes, guids), built at runtime so that no
// literal in the repository matches a secret scanner's hex-key pattern.

/// [length] hex digits cycling `0..f`, offset by [seed].
String fakeHex(int length, {int seed = 0}) =>
    List.generate(length, (i) => '0123456789abcdef'[(i + seed) % 16]).join();
