// SPDX-License-Identifier: GPL-3.0-or-later

/// Tolerant JSON readers. Required fields throw [FormatException] when absent
/// or mistyped; optional fields yield a default instead.
abstract final class JsonRead {
  static int requiredInt(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is int) return v;
    throw FormatException('field "$key" must be an integer');
  }

  static String requiredString(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is String) return v;
    throw FormatException('field "$key" must be a string');
  }

  static String? string(Map<String, Object?> m, String key) {
    final v = m[key];
    return v is String ? v : null;
  }

  static int? intOrNull(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is double && v.isFinite) return v.toInt();
    return null;
  }

  static int integer(Map<String, Object?> m, String key) =>
      intOrNull(m, key) ?? 0;

  static double decimal(Map<String, Object?> m, String key) {
    final v = m[key];
    return v is num && v.isFinite ? v.toDouble() : 0;
  }

  static bool boolean(Map<String, Object?> m, String key) {
    final v = m[key];
    return v is bool && v;
  }

  static DateTime? date(Map<String, Object?> m, String key) {
    final v = m[key];
    return v is String ? DateTime.tryParse(v) : null;
  }

  static List<Object?> list(Map<String, Object?> m, String key) {
    final v = m[key];
    return v is List ? v : const [];
  }

  static Map<String, Object?>? map(Object? v) {
    if (v is! Map) return null;
    return {
      for (final e in v.entries)
        if (e.key is String) e.key as String: e.value,
    };
  }
}
