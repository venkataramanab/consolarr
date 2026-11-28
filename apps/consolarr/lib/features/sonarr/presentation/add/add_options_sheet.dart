// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/add_options_form.dart';
import 'package:consolarr/features/arr_common/presentation/release_row.dart'
    show ArrBusyIndicator;
import 'package:consolarr/features/sonarr/application/add_series.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:consolarr/shared/widgets/inline_retry_row.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the options sheet to add [lookup] (SON-19).
Future<void> showAddOptionsSheet({
  required BuildContext context,
  required SonarrLookupResult lookup,
}) => showGlassSheet<void>(
  context: context,
  title: lookup.series.title,
  closeLabel: context.l10n.sonarrAddClose,
  detents: GlassSheetDetents.full,
  // The sheet paints its own surface: tiles need a Material of their own.
  scrollBuilder: (context, controller) => Material(
    type: MaterialType.transparency,
    child: AddOptionsBody(lookup: lookup, controller: controller),
  ),
);

String _typeLabel(AppLocalizations l10n, SeriesType t) => switch (t) {
  SeriesType.standard || SeriesType.unknown => l10n.sonarrAddTypeStandard,
  SeriesType.daily => l10n.sonarrAddTypeDaily,
  SeriesType.anime => l10n.sonarrAddTypeAnime,
};

String _monitorLabel(AppLocalizations l10n, SonarrMonitorPreset p) =>
    switch (p) {
      SonarrMonitorPreset.all => l10n.sonarrAddMonitorAll,
      SonarrMonitorPreset.future => l10n.sonarrAddMonitorFuture,
      SonarrMonitorPreset.missing => l10n.sonarrAddMonitorMissing,
      SonarrMonitorPreset.existing => l10n.sonarrAddMonitorExisting,
      SonarrMonitorPreset.firstSeason => l10n.sonarrAddMonitorFirstSeason,
      SonarrMonitorPreset.lastSeason => l10n.sonarrAddMonitorLastSeason,
      SonarrMonitorPreset.latestSeason => l10n.sonarrAddMonitorLatestSeason,
      SonarrMonitorPreset.pilot => l10n.sonarrAddMonitorPilot,
      SonarrMonitorPreset.none => l10n.sonarrAddMonitorNone,
    };

/// The sheet content: options form, saving state and the success
/// confirmation.
class AddOptionsBody extends ConsumerStatefulWidget {
  const AddOptionsBody({required this.lookup, this.controller, super.key});

  final SonarrLookupResult lookup;
  final ScrollController? controller;

  @override
  ConsumerState<AddOptionsBody> createState() => _AddOptionsBodyState();
}

class _AddOptionsBodyState extends ConsumerState<AddOptionsBody> {
  int? _profileId;
  String? _rootPath;
  SeriesType _type = SeriesType.standard;
  SonarrMonitorPreset _monitor = SonarrMonitorPreset.all;
  bool _seasonFolder = true;
  bool _monitored = true;
  final Set<int> _tags = {};
  final List<ArrTag> _created = [];

  void _init(AddFormData data) {
    _profileId ??= data.profiles.isEmpty ? null : data.profiles.first.id;
    _rootPath ??= data.defaultRootFolder?.path;
  }

  Future<String?> _createTag(String label) async {
    final result = await ref.read(createTagProvider)(label);
    final tag = result.valueOrNull;
    if (tag == null) return context.l10n.sonarrAddTagFailed;
    setState(() {
      _created.add(tag);
      _tags.add(tag.id);
    });
    return null;
  }

  void _submit({required bool search}) {
    final profile = _profileId;
    final root = _rootPath;
    if (profile == null || root == null) return;
    unawaited(
      ref
          .read(addSeriesProvider.notifier)
          .submit(
            widget.lookup,
            SonarrAddOptions(
              qualityProfileId: profile,
              rootFolderPath: root,
              seriesType: _type,
              monitor: _monitor,
              seasonFolder: _seasonFolder,
              monitored: _monitored,
              tags: _tags.toList()..sort(),
              searchForMissing: search,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final add = ref.watch(addSeriesProvider);
    if (add case AddSuccess(:final series, :final searched)) {
      return _Success(
        seriesId: series.id,
        searched: searched,
        onAnother: () => Navigator.of(context).pop(),
      );
    }
    final form = ref.watch(addFormDataProvider);
    // Loading and error before data: a reload keeps the previous value.
    if (form.isLoading) {
      return Semantics(
        label: l10n.sonarrAddOptionsLoading,
        liveRegion: true,
        child: const ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.all(ConsolarrSpacing.gutter),
            child: SkeletonBox(height: 240, borderRadius: ConsolarrRadii.card),
          ),
        ),
      );
    }
    if (form.hasError) {
      final error = form.error;
      final message = connectionErrorMessage(
        l10n,
        error is AppError ? error : const AppError(ErrorCategory.parseError),
      );
      return ErrorState(
        headline: l10n.sonarrAddOptionsErrorHeadline,
        message: message.message,
        hint: message.hint,
        retryLabel: l10n.sonarrAddRetry,
        onRetry: () => ref.invalidate(addFormDataProvider),
      );
    }
    final data = form.requireValue;
    if (!data.isUsable) {
      return EmptyState(
        icon: Icons.settings_outlined,
        headline: l10n.sonarrAddUnusableHeadline,
        message: l10n.sonarrAddUnusableMessage,
      );
    }
    _init(data);
    final busy = add is AddSubmitting;
    final tags = [...data.tags, ..._created];
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.sm,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.xl,
      ),
      children: [
        ArrOptionPicker<int>(
          label: l10n.sonarrAddOptionProfile,
          value: _profileId,
          options: [for (final p in data.profiles) ArrOption(p.id, p.name)],
          onChanged: (v) => setState(() => _profileId = v),
        ),
        ArrOptionPicker<String>(
          label: l10n.sonarrAddOptionRootFolder,
          value: _rootPath,
          options: [
            for (final f in data.rootFolders) ArrOption(f.path, f.path),
          ],
          onChanged: (v) => setState(() => _rootPath = v),
        ),
        ArrOptionPicker<SeriesType>(
          label: l10n.sonarrAddOptionSeriesType,
          value: _type,
          options: [
            for (final t in const [
              SeriesType.standard,
              SeriesType.daily,
              SeriesType.anime,
            ])
              ArrOption(t, _typeLabel(l10n, t)),
          ],
          onChanged: (v) => setState(() => _type = v),
        ),
        ArrOptionPicker<SonarrMonitorPreset>(
          label: l10n.sonarrAddOptionMonitor,
          value: _monitor,
          options: [
            for (final p in SonarrMonitorPreset.values)
              ArrOption(p, _monitorLabel(l10n, p)),
          ],
          onChanged: (v) => setState(() => _monitor = v),
        ),
        ArrOptionSwitch(
          title: l10n.sonarrAddOptionSeasonFolders,
          value: _seasonFolder,
          onChanged: (v) => setState(() => _seasonFolder = v),
        ),
        ArrOptionSwitch(
          title: l10n.sonarrAddOptionMonitored,
          subtitle: l10n.sonarrAddOptionMonitoredHint,
          value: _monitored,
          onChanged: (v) => setState(() => _monitored = v),
        ),
        ArrTagPicker(
          tags: [for (final t in tags) ArrTagOption(t.id, t.label)],
          selected: _tags,
          labels: ArrTagPickerLabels(
            heading: l10n.sonarrAddOptionTags,
            none: l10n.sonarrAddOptionNoTags,
            newTag: l10n.sonarrAddOptionNewTag,
            addTag: l10n.sonarrAddOptionCreateTag,
          ),
          onToggle: (id) => setState(
            () => _tags.contains(id) ? _tags.remove(id) : _tags.add(id),
          ),
          onCreate: _createTag,
        ),
        if (data.tagsFailed)
          InlineRetryRow(
            message: l10n.sonarrAddTagsFailed,
            retryLabel: l10n.sonarrRetry,
            onRetry: () => ref.invalidate(addFormDataProvider),
          ),
        if (add case AddFailed(:final error))
          _Failure(error: error, onRetry: () => _submit(search: false)),
        if (busy)
          Semantics(
            liveRegion: true,
            label: l10n.sonarrAddAdding,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                child: Row(
                  children: [
                    const ArrBusyIndicator(),
                    const SizedBox(width: ConsolarrSpacing.sm),
                    Flexible(child: Text(l10n.sonarrAddAdding)),
                  ],
                ),
              ),
            ),
          ),
        FilledButton(
          onPressed: busy ? null : () => _submit(search: false),
          child: Text(l10n.sonarrAddButton),
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        FilledButton.tonal(
          onPressed: busy ? null : () => _submit(search: true),
          child: Text(l10n.sonarrAddAndSearchButton),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});

  final AppError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = connectionErrorMessage(l10n, error);
    return Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusChip(
              label: l10n.sonarrAddFailedHeadline,
              icon: Icons.error_outline,
              tone: StatusTone.warning,
            ),
            const SizedBox(height: ConsolarrSpacing.xs),
            Text('${message.message} ${message.hint}'),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.sonarrAddRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({
    required this.seriesId,
    required this.searched,
    required this.onAnother,
  });

  final int seriesId;
  final bool searched;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final router = GoRouter.maybeOf(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: Icons.check_circle_outline,
              headline: l10n.sonarrAddSuccessHeadline,
              message: searched
                  ? l10n.sonarrAddSuccessSearching
                  : l10n.sonarrAddSuccessMessage,
              actionLabel: l10n.sonarrAddOpenSeries,
              onAction: () {
                Navigator.of(context).pop();
                unawaited(router?.push<void>(sonarrSeriesLocation(seriesId)));
              },
            ),
          ),
          TextButton(onPressed: onAnother, child: Text(l10n.sonarrAddAnother)),
          const SizedBox(height: ConsolarrSpacing.md),
        ],
      ),
    );
  }
}
