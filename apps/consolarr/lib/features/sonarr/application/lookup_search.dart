// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State of the add-series search (SON-19).
sealed class LookupState {
  const LookupState();
}

/// Nothing searched yet (or the term was cleared).
final class LookupIdle extends LookupState {
  const LookupIdle();
}

final class LookupSearching extends LookupState {
  const LookupSearching();
}

/// Search results, possibly empty.
final class LookupResults extends LookupState {
  const LookupResults(this.results);
  final List<SonarrLookupResult> results;
}

final class LookupFailed extends LookupState {
  const LookupFailed(this.error);
  final AppError error;
}

/// Longest search term sent to the server.
const lookupMaxTermLength = 100;

/// Most results shown.
const lookupMaxResults = 50;

/// Normalizes user input to a search term, or null when it is too short or
/// holds control characters. `tvdb:123` and `imdb:tt123` pass through.
String? normalizeLookupTerm(String raw) {
  final term = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (term.length < 2) return null;
  if (RegExp(r'[\u0000-\u001f\u007f]').hasMatch(term)) return null;
  return term.length > lookupMaxTermLength
      ? term.substring(0, lookupMaxTermLength)
      : term;
}

/// The series lookup. Only the latest search counts: an older, slower answer
/// is dropped.
final lookupSearchProvider =
    NotifierProvider.autoDispose<LookupSearchNotifier, LookupState>(
      LookupSearchNotifier.new,
    );

class LookupSearchNotifier extends Notifier<LookupState> {
  int _token = 0;

  @override
  LookupState build() => const LookupIdle();

  /// Searches for [raw]; a blank or too short term resets to idle.
  Future<void> search(String raw) async {
    final token = ++_token;
    final term = normalizeLookupTerm(raw);
    if (term == null) {
      state = const LookupIdle();
      return;
    }
    state = const LookupSearching();
    final SonarrSession? session;
    try {
      session = await ref.read(sonarrSessionProvider.future);
    } on AppError catch (error) {
      if (ref.mounted && token == _token) state = LookupFailed(error);
      return;
    }
    if (session == null) {
      if (ref.mounted && token == _token) {
        state = const LookupFailed(AppError(ErrorCategory.notFound));
      }
      return;
    }
    final result = await session.api.lookup(term);
    if (!ref.mounted || token != _token) return;
    state = result.when(
      ok: (list) => LookupResults(
        list.length > lookupMaxResults
            ? list.sublist(0, lookupMaxResults)
            : list,
      ),
      err: LookupFailed.new,
    );
  }
}
