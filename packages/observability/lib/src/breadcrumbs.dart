// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/src/events/catalog.dart';
import 'package:observability/src/redactor.dart';

/// One breadcrumb: a closed-set fact (a screen, or an API error category for a
/// service kind). It cannot carry free text, URLs, hosts or titles.
final class Breadcrumb {
  const Breadcrumb._(this.line);

  /// The user navigated to [screen].
  factory Breadcrumb.navigation(ScreenName screen) =>
      Breadcrumb._(_safe('nav ${screen.code}'));

  /// An API call to a [service] failed with [category].
  factory Breadcrumb.apiError(
    ErrorCategoryParam category,
    ServiceKindParam service,
  ) => Breadcrumb._(_safe('api_error ${category.code} ${service.code}'));

  /// Defence in depth: every serialised crumb passes through the redactor.
  static String _safe(String raw) => const Redactor().redactText(raw);

  /// The serialised, redacted crumb.
  final String line;

  @override
  bool operator ==(Object other) => other is Breadcrumb && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => line;
}

/// A bounded in-memory trail attached to crash reports (only when the user
/// opted in). Oldest entries are dropped first.
class Breadcrumbs {
  Breadcrumbs({this.capacity = 50}) : assert(capacity > 0, 'capacity > 0');

  final int capacity;
  final List<Breadcrumb> _entries = [];

  /// Whether a crumb may be kept right now. The consent manager sets it to
  /// "crash-report consent is on", so nothing is collected, not even in
  /// memory, while the user has not opted in. Default: never, so nothing is kept
  /// before the consent state is known (the manager is built after the first
  /// frame).
  bool Function() recordingAllowed = _never;

  static bool _never() => false;

  /// Oldest first.
  List<Breadcrumb> get entries => List.unmodifiable(_entries);

  void add(Breadcrumb crumb) {
    if (!recordingAllowed()) return;
    _entries.add(crumb);
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  void clear() => _entries.clear();
}
