// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/radarr_routes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'switching.dart';

void main() {
  group('L2: movie ids from a link', () {
    test('only plain positive 32-bit numbers parse', () {
      for (final bad in [
        null,
        '',
        '0',
        '-1',
        '01',
        ' 1',
        '1 ',
        '1.5',
        '2147483648',
        '99999999999',
        '0x10',
        'abc',
      ]) {
        expect(parseMovieId(bad), isNull, reason: '$bad');
      }
      expect(parseMovieId('1'), 1);
      expect(parseMovieId('2147483647'), 2147483647);
    });

    test('an impossible id is gone at once, with no request', () async {
      final api = GatedApi();
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      for (final id in [-1, 0]) {
        final state = await c.read(movieDetailProvider(id).future);
        expect(state, isA<RadarrGone<RadarrMovie>>());
      }
      expect(api.movieCalls, 0);
      expect(api.moviesCalls, 0);
    });
  });
}
