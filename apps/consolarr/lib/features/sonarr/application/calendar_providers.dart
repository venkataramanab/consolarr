// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/calendar_repository.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:consolarr/features/sonarr/data/calendar_repository.dart'
    show CalendarSnapshot;

/// Days shown by one page of the range list.
const calendarRangeDays = 14;

/// List of day groups, or a month grid.
enum CalendarMode { range, month }

/// What the calendar shows: mode, window and the unmonitored switch.
@immutable
class CalendarView {
  const CalendarView({
    required this.mode,
    required this.anchor,
    required this.includeUnmonitored,
    this.selectedDay,
  });

  final CalendarMode mode;

  /// First day of the range list, or any day of the shown month.
  final DateTime anchor;
  final bool includeUnmonitored;

  /// Day picked in the month view (local date, midnight).
  final DateTime? selectedDay;

  /// Local-midnight start of the window.
  DateTime get start =>
      mode == CalendarMode.range ? anchor : DateTime(anchor.year, anchor.month);

  /// Local-midnight end (exclusive) of the window.
  DateTime get end => mode == CalendarMode.range
      ? DateTime(anchor.year, anchor.month, anchor.day + calendarRangeDays)
      : DateTime(anchor.year, anchor.month + 1);

  CalendarView copyWith({
    CalendarMode? mode,
    DateTime? anchor,
    bool? includeUnmonitored,
    DateTime? selectedDay,
    bool clearSelection = false,
  }) => CalendarView(
    mode: mode ?? this.mode,
    anchor: anchor ?? this.anchor,
    includeUnmonitored: includeUnmonitored ?? this.includeUnmonitored,
    selectedDay: clearSelection ? null : (selectedDay ?? this.selectedDay),
  );

  @override
  bool operator ==(Object other) =>
      other is CalendarView &&
      other.mode == mode &&
      other.anchor == anchor &&
      other.includeUnmonitored == includeUnmonitored &&
      other.selectedDay == selectedDay;

  @override
  int get hashCode =>
      Object.hash(mode, anchor, includeUnmonitored, selectedDay);
}

DateTime _today(DateTime now) => DateTime(now.year, now.month, now.day);

/// The calendar's view settings. Not persisted: it always opens on today.
final calendarViewProvider =
    NotifierProvider<CalendarViewNotifier, CalendarView>(
      CalendarViewNotifier.new,
    );

class CalendarViewNotifier extends Notifier<CalendarView> {
  @override
  CalendarView build() => CalendarView(
    mode: CalendarMode.range,
    anchor: _today(ref.read(clockProvider)().toLocal()),
    includeUnmonitored: false,
  );

  DateTime get _now => _today(ref.read(clockProvider)().toLocal());

  void setMode(CalendarMode mode) =>
      state = state.copyWith(mode: mode, anchor: _now, clearSelection: true);

  void toggleUnmonitored() =>
      state = state.copyWith(includeUnmonitored: !state.includeUnmonitored);

  /// Back to today (range list from today, or the current month selected on
  /// today).
  void today() => state = state.copyWith(anchor: _now, selectedDay: _now);

  /// Moves the window by one page (range) or month (month view).
  void step(int direction) {
    final a = state.anchor;
    state = state.copyWith(
      anchor: state.mode == CalendarMode.range
          ? DateTime(a.year, a.month, a.day + direction * calendarRangeDays)
          : DateTime(a.year, a.month + direction),
      clearSelection: true,
    );
  }

  void selectDay(DateTime? day) => state = day == null
      ? state.copyWith(clearSelection: true)
      : state.copyWith(selectedDay: day);
}

/// What the calendar tab shows.
sealed class CalendarState {
  const CalendarState();
}

final class CalendarNoServer extends CalendarState {
  const CalendarNoServer();
}

/// Nothing to show: the load failed and no usable cached copy exists.
final class CalendarFailure extends CalendarState {
  const CalendarFailure(this.error);
  final AppError error;
}

/// Episodes of the window, live or cached.
final class CalendarData extends CalendarState {
  const CalendarData(this.snapshot, this.view);
  final CalendarSnapshot snapshot;
  final CalendarView view;

  bool get isOffline => snapshot.isOffline;
}

/// The calendar of the active server for the current [CalendarView]. A server
/// switch or window change is a reload: screens check `isLoading` and
/// `hasError` before reading `value`.
final calendarProvider = AsyncNotifierProvider<CalendarNotifier, CalendarState>(
  CalendarNotifier.new,
  retry: (_, _) => null,
);

class CalendarNotifier extends AsyncNotifier<CalendarState> {
  CalendarRepository? _repository;
  CalendarView? _view;
  int _generation = 0;

  @override
  Future<CalendarState> build() async {
    _generation++;
    _repository = null;
    final view = ref.watch(calendarViewProvider);
    _view = view;
    final SonarrSession? session;
    try {
      session = await ref.watch(sonarrSessionProvider.future);
    } on AppError catch (error) {
      return CalendarFailure(error);
    }
    if (session == null) return const CalendarNoServer();
    final repository = CalendarRepository(
      api: session.api,
      cache: session.cache,
      serverId: session.serverId,
      clock: session.clock,
    );
    _repository = repository;
    return _load(repository, view);
  }

  Future<CalendarState> _load(CalendarRepository r, CalendarView view) async {
    final result = await r.load(
      start: view.start,
      end: view.end,
      includeUnmonitored: view.includeUnmonitored,
    );
    return result.when(
      ok: (s) => CalendarData(s, view),
      err: CalendarFailure.new,
    );
  }

  /// Reloads without clearing what is on screen. Dropped when the server or
  /// window changed meanwhile.
  Future<void> refresh() async {
    final repository = _repository;
    final view = _view;
    if (repository == null || view == null) {
      if (state.isLoading) return;
      ref.invalidateSelf();
      await future;
      return;
    }
    final generation = _generation;
    final previous = state.value;
    final next = await _load(repository, view);
    if (!ref.mounted || generation != _generation) return;
    if (next is CalendarFailure &&
        previous is CalendarData &&
        kOfflineFallbackCategories.contains(next.error.category)) {
      state = AsyncData(
        CalendarData(
          CalendarSnapshot(
            episodes: previous.snapshot.episodes,
            fetchedAt: previous.snapshot.fetchedAt,
            offlineError: next.error,
          ),
          view,
        ),
      );
      return;
    }
    state = AsyncData(next);
  }
}

/// Groups [episodes] by local day, sorted by air time. Keys are local-midnight
/// dates; episodes without an air date are left out.
Map<DateTime, List<SonarrEpisode>> groupByDay(List<SonarrEpisode> episodes) {
  final sorted = [...episodes]
    ..sort((a, b) => (a.airs ?? DateTime(0)).compareTo(b.airs ?? DateTime(0)));
  final out = <DateTime, List<SonarrEpisode>>{};
  for (final e in sorted) {
    final airs = e.airs?.toLocal();
    if (airs == null) continue;
    out.putIfAbsent(DateTime(airs.year, airs.month, airs.day), () => []).add(e);
  }
  return out;
}
