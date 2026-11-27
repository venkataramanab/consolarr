// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';

/// Identity of one certificate pin: the server profile it was made for, the
/// normalised host and the explicit port.
///
/// Pins are never shared between profiles or ports: trusting
/// `nas.example:443` says nothing about `nas.example:8443`, and two profiles
/// that happen to point at the same host pin independently.
///
/// Normalisation: host lower-cased, trailing dot removed, IPv6 brackets
/// removed; the port is always explicit (443 / 80 for scheme defaults).
final class PinKey {
  PinKey._(this.profileId, this.host, this.port);

  /// Builds a key from raw parts.
  ///
  /// Throws [ArgumentError] when [profileId] or [host] is empty/contains
  /// whitespace or control characters, or [port] is outside 1..65535.
  factory PinKey({
    required String profileId,
    required String host,
    required int port,
  }) {
    if (!_validId.hasMatch(profileId)) {
      throw ArgumentError.value(profileId, 'profileId', 'invalid');
    }
    var h = host.trim().toLowerCase();
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    if (h.isEmpty || h.contains(_forbiddenInHost)) {
      throw ArgumentError.value(host, 'host', 'invalid');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be 1..65535');
    }
    return PinKey._(profileId, h, port);
  }

  /// The key for the server described by [profile].
  ///
  /// [ServerProfile.address] is an absolute http(s) URL, so [Uri.port] is the
  /// explicit port or the scheme default.
  factory PinKey.forProfile(ServerProfile profile) => PinKey(
    profileId: profile.id,
    host: profile.address.host,
    port: profile.address.port,
  );

  static final _validId = RegExp(r'^[^\s\x00-\x1f\x7f]{1,128}$');
  static final _forbiddenInHost = RegExp(r'[\s\x00-\x1f\x7f/@?#\\]');

  /// Server profile id (`ServerProfile.id`).
  final String profileId;

  /// Normalised host name or IP address (no brackets, no trailing dot).
  final String host;

  /// Explicit TCP port.
  final int port;

  /// Stable, injective storage key (components are percent-encoded so no
  /// profile id or host can collide with another key).
  String get storageKey =>
      'pin/v1/${Uri.encodeComponent(profileId)}/${Uri.encodeComponent(host)}/$port';

  @override
  bool operator ==(Object other) =>
      other is PinKey &&
      other.profileId == profileId &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(profileId, host, port);

  /// Omits the host so logs never carry it.
  @override
  String toString() => 'PinKey($profileId, port $port)';
}
