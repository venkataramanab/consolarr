// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';

/// Latin text inside an Arabic sentence is wrapped in a left-to-right isolate
/// (LRI U+2066 ... PDI U+2069) so it keeps its own order and does not pull the
/// punctuation around it into the wrong place.
final _lri = String.fromCharCode(0x2066);
final _pdi = String.fromCharCode(0x2069);

/// The Sonarr and Radarr web interface is usually in English, so the menu path
/// is quoted as it appears there.
const _path = 'Settings → General → Security';

void main() {
  late AppLocalizations ar;
  setUp(() async {
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  for (final service in ['Sonarr', 'Radarr']) {
    test('the API key helper isolates $service and the English menu path', () {
      final text = ar.serverApiKeyHelper(service);
      expect(text, contains('$_lri$service$_pdi'));
      expect(text, contains('«$_lri$_path$_pdi»'));
      expect(text, isNot(contains('←')), reason: 'no translated menu path');
    });

    test('the arr auth hint isolates $service and the English menu path', () {
      final text = ar.connErrorArrAuthFailedHint(service);
      expect(text, contains('$_lri$service$_pdi'));
      expect(text, contains('«$_lri$_path$_pdi»'));
      expect(text, isNot(contains('←')), reason: 'no translated menu path');
    });
  }

  test('every isolate is closed', () {
    for (final text in [
      ar.serverApiKeyHelper('Sonarr'),
      ar.connErrorArrAuthFailedHint('Radarr'),
    ]) {
      expect(_lri.allMatches(text).length, _pdi.allMatches(text).length);
    }
  });
}
