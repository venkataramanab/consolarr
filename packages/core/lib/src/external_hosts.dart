// SPDX-License-Identifier: GPL-3.0-or-later

/// Every host the app can open **on a user tap**, in the browser or the
/// site's app. The app never contacts these by itself.
///
/// Call sites build their links from these constants, and a test requires
/// each host to be named in the About privacy statement (en and ar) and in
/// `README.md`. Add a new host here **and** to those texts, or CI fails.
abstract final class ExternalHosts {
  /// "Source code" and the pre-filled issue.
  static const github = 'github.com';

  /// Radarr movie trailer.
  static const youtube = 'www.youtube.com';

  /// Sonarr series information links.
  static const imdb = 'www.imdb.com';
  static const tvdb = 'thetvdb.com';
  static const tmdb = 'www.themoviedb.org';
  static const tvMaze = 'www.tvmaze.com';

  /// All of them; the privacy statement must name each one.
  static const all = <String>[github, youtube, imdb, tvdb, tmdb, tvMaze];
}
