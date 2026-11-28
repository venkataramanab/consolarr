// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:test/test.dart';

import '../support/fake_adapter.dart';

RadarrClient _client(String base) => RadarrClient(
  dio: dioWith(FakeAdapter.fixed('[]'), base: base),
  parseRunner: <T>(T Function() c) async => c(),
);

ArrImage _img(ArrImageType type, String? url) => ArrImage(type: type, url: url);

void main() {
  group('artworkUriFor URL shapes', () {
    final c = _client('https://radarr.example');

    test('plain MediaCover path', () {
      final u = c.artworkUriFor([
        _img(ArrImageType.poster, '/MediaCover/7/poster.jpg'),
      ], ArrImageType.poster)!;
      expect(u.toString(), 'https://radarr.example/MediaCover/7/poster.jpg');
    });

    test('keeps the ?h= and ?lastWrite= cache-busting queries', () {
      final h = c.artworkUriFor([
        _img(
          ArrImageType.poster,
          '/MediaCover/7/poster.jpg?h=0123456789abcdef0123',
        ),
      ], ArrImageType.poster)!;
      expect(h.path, '/MediaCover/7/poster.jpg');
      expect(h.queryParameters, {'h': '0123456789abcdef0123'});
      final w = c.artworkUriFor([
        _img(
          ArrImageType.poster,
          '/MediaCover/7/poster-500.jpg?lastWrite=638000000000000000',
        ),
      ], ArrImageType.poster)!;
      expect(w.path, '/MediaCover/7/poster-500.jpg');
      expect(w.queryParameters, {'lastWrite': '638000000000000000'});
    });

    test('lookup results use /MediaCoverProxy/<hash>/<file>', () {
      final hash = 'ab' * 32;
      final u = c.artworkUriFor([
        _img(ArrImageType.poster, '/MediaCoverProxy/$hash/f1a2b3c4.jpg'),
      ], ArrImageType.poster)!;
      expect(u.path, '/MediaCoverProxy/$hash/f1a2b3c4.jpg');
      expect(u.host, 'radarr.example');
    });

    test('a urlBase the server already put in the URL is not doubled', () {
      final nested = _client('https://radarr.example/media/radarr');
      final already = nested.artworkUriFor([
        _img(
          ArrImageType.poster,
          '/media/radarr/MediaCover/7/poster.jpg?h=abc',
        ),
      ], ArrImageType.poster)!;
      expect(already.path, '/media/radarr/MediaCover/7/poster.jpg');
      final bare = nested.artworkUriFor([
        _img(ArrImageType.poster, '/MediaCover/7/poster.jpg'),
      ], ArrImageType.poster)!;
      expect(bare.path, '/media/radarr/MediaCover/7/poster.jpg');
      // A prefix that merely starts the same is a different path.
      final lookalike = nested.artworkUriFor([
        _img(ArrImageType.poster, '/media/radarrx/MediaCover/7/poster.jpg'),
      ], ArrImageType.poster)!;
      expect(
        lookalike.path,
        '/media/radarr/media/radarrx/MediaCover/7/poster.jpg',
      );
    });

    test('never an absolute URL, a scheme-relative one or a secret query', () {
      for (final bad in [
        'https://image.tmdb.example/p.jpg',
        '//image.tmdb.example/p.jpg',
        'MediaCover/7/poster.jpg',
      ]) {
        expect(
          c.artworkUriFor([
            _img(ArrImageType.poster, bad),
          ], ArrImageType.poster),
          isNull,
          reason: bad,
        );
      }
      final u = c.artworkUriFor([
        _img(
          ArrImageType.poster,
          '/MediaCover/7/poster.jpg?apikey=k&h=x&token=t',
        ),
      ], ArrImageType.poster)!;
      expect(u.queryParameters, {'h': 'x'});
    });
  });

  group('poster fallback chain', () {
    final c = _client('https://radarr.example');
    final poster = _img(ArrImageType.poster, '/MediaCover/1/poster.jpg');
    final cover = _img(ArrImageType.cover, '/MediaCover/1/cover.jpg');
    final banner = _img(ArrImageType.banner, '/MediaCover/1/banner.jpg');
    final fanart = _img(ArrImageType.fanart, '/MediaCover/1/fanart.jpg');

    String? poster0(List<ArrImage> images) =>
        c.artworkUriFor(images, ArrImageType.poster)?.path;

    test('a poster always wins', () {
      expect(
        poster0([fanart, banner, cover, poster]),
        '/MediaCover/1/poster.jpg',
      );
    });

    test('without a poster: cover, then banner, then fanart', () {
      expect(poster0([fanart, banner, cover]), '/MediaCover/1/cover.jpg');
      expect(poster0([fanart, banner]), '/MediaCover/1/banner.jpg');
      expect(poster0([fanart]), '/MediaCover/1/fanart.jpg');
      expect(poster0(const []), isNull);
    });

    test('a poster without a usable url falls through to the next type', () {
      final empty = _img(ArrImageType.poster, '');
      final remote = _img(ArrImageType.poster, 'https://other.example/p.jpg');
      expect(poster0([empty, remote, cover]), '/MediaCover/1/cover.jpg');
      expect(
        poster0([_img(ArrImageType.poster, null), fanart]),
        '/MediaCover/1/fanart.jpg',
      );
    });

    test('other types do not fall back', () {
      expect(c.artworkUriFor([poster, banner], ArrImageType.fanart), isNull);
      expect(c.artworkUriFor([poster], ArrImageType.banner), isNull);
    });

    test('the cover type parses and round-trips', () {
      final parsed = ArrImage.fromJson({
        'coverType': 'cover',
        'url': '/MediaCover/1/cover.jpg',
      });
      expect(parsed.type, ArrImageType.cover);
      expect(ArrImage.fromJson(parsed.toJson()), parsed);
    });
  });

  group('posterSizeVariantUri', () {
    final c = _client('https://radarr.example');

    test('swaps the file for the 500 pixel variant and drops the query', () {
      final u = Uri.parse(
        'https://radarr.example/p/MediaCover/7/poster.jpg?h=abc',
      );
      expect(
        posterSizeVariantUri(u, 500)!.toString(),
        'https://radarr.example/p/MediaCover/7/poster-500.jpg',
      );
      expect(
        posterSizeVariantUri(u, 250)!.path,
        '/p/MediaCover/7/poster-250.jpg',
      );
    });

    test('only for a plain poster file of the served MediaCover tree', () {
      for (final s in [
        'https://radarr.example/MediaCover/7/poster-500.jpg',
        'https://radarr.example/MediaCover/7/fanart.jpg',
        'https://radarr.example/MediaCoverProxy/${'a' * 64}/x.jpg',
      ]) {
        expect(posterSizeVariantUri(Uri.parse(s), 500), isNull, reason: s);
      }
      expect(
        posterSizeVariantUri(
          Uri.parse('https://radarr.example/MediaCover/7/poster.jpg'),
          300,
        ),
        isNull,
      );
    });
  });
}
