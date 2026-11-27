// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('supports en, ar and the en_XA pseudo-locale', () {
    final tags = AppLocalizations.supportedLocales
        .map((l) => l.toLanguageTag())
        .toSet();
    expect(tags, containsAll(['en', 'ar', 'en-XA']));
  });

  test('plural forms resolve per locale', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.homeServerCount(0), 'No servers');
    expect(en.homeServerCount(1), '1 server');
    expect(en.homeServerCount(5), '5 servers');
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(ar.homeServerCount(2), 'خادمان');
    final xa = await AppLocalizations.delegate.load(const Locale('en', 'XA'));
    expect(xa.homeServerCount(5), contains('5'));
    expect(xa.homeTitle, isNot('Home'));
  });

  test('app delegates include Material localizations for every locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      expect(
        appLocalizationsDelegates.any(
          (d) => d.type == MaterialLocalizations && d.isSupported(locale),
        ),
        isTrue,
        reason: '$locale',
      );
    }
  });
}
