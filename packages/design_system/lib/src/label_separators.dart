// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// The punctuation that joins the parts of a spoken or shown label ("Title,
/// subtitle" and "2020 · 4 GB"). The design system has no l10n, so the app
/// provides the localized marks once, near the root, through
/// [ConsolarrSeparatorsScope] (from the `sharedListSeparator` and
/// `sharedPartSeparator` messages). Without a scope (previews, tests) the
/// marks default to the locale's own: the Arabic comma in `ar`.
///
/// This is the only design-system file that spells these marks out.
@immutable
class ConsolarrSeparators {
  const ConsolarrSeparators({required this.list, required this.part});

  /// Between the items of a list or the parts of a spoken label.
  final String list;

  /// Between the short facts of a visible line.
  final String part;

  /// The separators in effect for [context].
  static ConsolarrSeparators of(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<_SeparatorsInherited>();
    if (scoped != null) return scoped.separators;
    final arabic = Localizations.maybeLocaleOf(context)?.languageCode == 'ar';
    return ConsolarrSeparators(list: arabic ? '، ' : ', ', part: ' · ');
  }

  /// [parts] without the nulls and empty strings, joined with [list].
  String joinList(Iterable<String?> parts) => [
    for (final p in parts)
      if (p != null && p.isNotEmpty) p,
  ].join(list);

  /// [parts] without the nulls and empty strings, joined with [part].
  String joinParts(Iterable<String?> parts) => [
    for (final p in parts)
      if (p != null && p.isNotEmpty) p,
  ].join(part);

  @override
  bool operator ==(Object other) =>
      other is ConsolarrSeparators && other.list == list && other.part == part;

  @override
  int get hashCode => Object.hash(list, part);
}

class _SeparatorsInherited extends InheritedWidget {
  const _SeparatorsInherited({required this.separators, required super.child});

  final ConsolarrSeparators separators;

  @override
  bool updateShouldNotify(_SeparatorsInherited old) =>
      old.separators != separators;
}

/// Provides the localized [ConsolarrSeparators] to the widgets below.
class ConsolarrSeparatorsScope extends StatelessWidget {
  const ConsolarrSeparatorsScope({
    required this.list,
    required this.part,
    required this.child,
    super.key,
  });

  final String list;
  final String part;
  final Widget child;

  @override
  Widget build(BuildContext context) => _SeparatorsInherited(
    separators: ConsolarrSeparators(list: list, part: part),
    child: child,
  );
}
