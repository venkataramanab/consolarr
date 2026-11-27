// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/sort_filter_chip_bar.dart';
import 'package:consolarr/features/sonarr/application/library_providers.dart';
import 'package:consolarr/features/sonarr/application/library_query.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';

/// Localized name of a sort key.
String sortKeyLabel(AppLocalizations l10n, SeriesSortKey key) => switch (key) {
  SeriesSortKey.title => l10n.sonarrLibrarySortTitle,
  SeriesSortKey.year => l10n.sonarrLibrarySortYear,
  SeriesSortKey.added => l10n.sonarrLibrarySortAdded,
  SeriesSortKey.nextAiring => l10n.sonarrLibrarySortNextAiring,
  SeriesSortKey.network => l10n.sonarrLibrarySortNetwork,
  SeriesSortKey.size => l10n.sonarrLibrarySortSize,
  SeriesSortKey.rating => l10n.sonarrLibrarySortRating,
  SeriesSortKey.qualityProfile => l10n.sonarrLibrarySortProfile,
  SeriesSortKey.genre => l10n.sonarrLibrarySortGenre,
};

List<SortOption<SeriesSortKey>> sortOptions(AppLocalizations l10n) => [
  for (final k in SeriesSortKey.values)
    SortOption(key: k, label: sortKeyLabel(l10n, k)),
];

String typeLabel(AppLocalizations l10n, SeriesType t) => switch (t) {
  SeriesType.standard => l10n.sonarrLibraryTypeStandard,
  SeriesType.daily => l10n.sonarrLibraryTypeDaily,
  SeriesType.anime => l10n.sonarrLibraryTypeAnime,
  SeriesType.unknown => l10n.sonarrLibraryGroupUnknown,
};

const _selectableStatuses = [
  SeriesStatus.continuing,
  SeriesStatus.ended,
  SeriesStatus.upcoming,
];
const _selectableTypes = [
  SeriesType.standard,
  SeriesType.daily,
  SeriesType.anime,
];

/// Sections of the filter sheet.
List<FilterSection> filterSections(
  AppLocalizations l10n,
  LibraryLookups lookups,
) => [
  FilterSection(
    id: 'monitored',
    label: l10n.sonarrLibraryFilterMonitoring,
    multiSelect: false,
    chips: [
      FilterChoice(id: 'monitored', label: l10n.sonarrMonitored),
      FilterChoice(id: 'unmonitored', label: l10n.sonarrUnmonitored),
    ],
  ),
  FilterSection(
    id: 'status',
    label: l10n.sonarrLibraryFilterStatus,
    chips: [
      for (final s in _selectableStatuses)
        FilterChoice(id: s.name, label: statusText(l10n, s)!),
    ],
  ),
  FilterSection(
    id: 'type',
    label: l10n.sonarrLibraryFilterType,
    chips: [
      for (final t in _selectableTypes)
        FilterChoice(id: t.name, label: typeLabel(l10n, t)),
    ],
  ),
  if (lookups.profiles.isNotEmpty)
    FilterSection(
      id: 'profile',
      label: l10n.sonarrLibraryFilterProfile,
      chips: [
        for (final p in lookups.profiles)
          FilterChoice(id: '${p.id}', label: p.name),
      ],
    ),
  if (lookups.tags.isNotEmpty)
    FilterSection(
      id: 'tags',
      label: l10n.sonarrLibraryFilterTags,
      chips: [
        for (final t in lookups.tags)
          FilterChoice(id: '${t.id}', label: t.label),
      ],
    ),
];

/// The sheet's initial chip state for the current [filter].
FilterSelection filterSelection(LibraryFilter filter) => FilterSelection({
  if (filter.monitored != MonitoredFilter.any)
    'monitored': {
      filter.monitored == MonitoredFilter.monitored
          ? 'monitored'
          : 'unmonitored',
    },
  if (filter.statuses.isNotEmpty)
    'status': {for (final s in filter.statuses) s.name},
  if (filter.types.isNotEmpty) 'type': {for (final t in filter.types) t.name},
  if (filter.profileIds.isNotEmpty)
    'profile': {for (final id in filter.profileIds) '$id'},
  if (filter.tagIds.isNotEmpty) 'tags': {for (final id in filter.tagIds) '$id'},
});

/// Reads the sheet's selection back into a filter.
LibraryFilter filterFromSelection(FilterSelection selection) {
  Set<int> ints(String id) => {
    for (final v in selection.of(id))
      if (int.tryParse(v) case final n?) n,
  };
  final monitored = selection.of('monitored');
  return LibraryFilter(
    monitored: monitored.contains('monitored')
        ? MonitoredFilter.monitored
        : monitored.contains('unmonitored')
        ? MonitoredFilter.unmonitored
        : MonitoredFilter.any,
    statuses: {
      for (final s in _selectableStatuses)
        if (selection.of('status').contains(s.name)) s,
    },
    types: {
      for (final t in _selectableTypes)
        if (selection.of('type').contains(t.name)) t,
    },
    profileIds: ints('profile'),
    tagIds: ints('tags'),
  );
}

/// One removable chip per active criterion.
List<ArrActiveFilter> activeFilters(
  AppLocalizations l10n,
  LibraryFilter f,
  LibraryLookups lookups,
) {
  ArrActiveFilter chip(String id, String label) => ArrActiveFilter(
    id: id,
    label: label,
    removeLabel: l10n.sonarrLibraryRemoveFilter(label),
  );
  return [
    if (f.monitored != MonitoredFilter.any)
      chip(
        'monitored',
        f.monitored == MonitoredFilter.monitored
            ? l10n.sonarrMonitored
            : l10n.sonarrUnmonitored,
      ),
    for (final s in f.statuses)
      if (statusText(l10n, s) case final t?) chip('status:${s.name}', t),
    for (final t in f.types) chip('type:${t.name}', typeLabel(l10n, t)),
    for (final id in f.profileIds)
      if (lookups.profileNames[id] case final name?) chip('profile:$id', name),
    for (final id in f.tagIds)
      for (final tag in lookups.tags)
        if (tag.id == id) chip('tag:$id', tag.label),
  ];
}

/// The filter without the criterion behind chip [id].
LibraryFilter removeFilter(LibraryFilter f, String id) {
  if (id == 'monitored') {
    return LibraryFilter(
      statuses: f.statuses,
      types: f.types,
      profileIds: f.profileIds,
      tagIds: f.tagIds,
    );
  }
  final parts = id.split(':');
  final value = parts.length == 2 ? parts[1] : '';
  return LibraryFilter(
    monitored: f.monitored,
    statuses: parts[0] == 'status'
        ? {
            for (final s in f.statuses)
              if (s.name != value) s,
          }
        : f.statuses,
    types: parts[0] == 'type'
        ? {
            for (final t in f.types)
              if (t.name != value) t,
          }
        : f.types,
    profileIds: parts[0] == 'profile'
        ? f.profileIds.where((i) => '$i' != value).toSet()
        : f.profileIds,
    tagIds: parts[0] == 'tag'
        ? f.tagIds.where((i) => '$i' != value).toSet()
        : f.tagIds,
  );
}

/// Header text of a group.
String groupLabel(AppLocalizations l10n, GroupKey key) => switch (key) {
  GroupText(:final text) => text,
  GroupUnknown() => l10n.sonarrLibraryGroupUnknown,
  GroupScheduled(:final scheduled) =>
    scheduled
        ? l10n.sonarrLibraryGroupScheduled
        : l10n.sonarrLibraryGroupNotScheduled,
  GroupSize(:final bucket) => switch (bucket) {
    0 => l10n.sonarrLibraryGroupSizeSmall,
    1 => l10n.sonarrLibraryGroupSizeMedium,
    _ => l10n.sonarrLibraryGroupSizeLarge,
  },
  GroupRating(:final floor) => l10n.sonarrLibraryGroupRating(floor),
};
