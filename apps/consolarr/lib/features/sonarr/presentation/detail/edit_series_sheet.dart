// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the edit sheet (SON-11): monitored, quality profile and tags (with
/// inline tag creation). Resolves to true when the changes were saved.
Future<bool?> showEditSeriesSheet({
  required BuildContext context,
  required int seriesId,
}) => showGlassSheet<bool>(
  context: context,
  title: context.l10n.sonarrDetailEditTitle,
  closeLabel: context.l10n.sonarrDetailEditClose,
  // A long form with Save at the bottom: open it fully.
  detents: GlassSheetDetents.full,
  // The sheet paints its own surface: tiles need a Material of their own.
  scrollBuilder: (context, controller) => Material(
    type: MaterialType.transparency,
    child: EditSeriesForm(seriesId: seriesId, scrollController: controller),
  ),
);

/// The form inside the edit sheet.
class EditSeriesForm extends ConsumerStatefulWidget {
  const EditSeriesForm({
    required this.seriesId,
    this.scrollController,
    super.key,
  });

  final int seriesId;
  final ScrollController? scrollController;

  @override
  ConsumerState<EditSeriesForm> createState() => _EditSeriesFormState();
}

enum _Save { idle, saving, failed }

class _EditSeriesFormState extends ConsumerState<EditSeriesForm> {
  bool? _monitored;
  int? _profile;
  Set<int>? _tags;
  _Save _save = _Save.idle;
  final _newTag = TextEditingController();
  bool _creating = false;
  bool _tagFailed = false;
  final List<ArrTag> _created = [];

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  Future<void> _submit(DetailData data) async {
    if (_save == _Save.saving) return;
    setState(() => _save = _Save.saving);
    final detail = data.snapshot.detail;
    final error = await ref
        .read(seriesDetailProvider(widget.seriesId).notifier)
        .saveEdit(
          monitored: _monitored ?? detail.summary.monitored,
          qualityProfileId: _profile ?? detail.summary.qualityProfileId,
          tags: (_tags ?? detail.summary.tags.toSet()).toList()..sort(),
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _save = _Save.failed);
    }
  }

  Future<void> _addTag() async {
    final label = _newTag.text.trim();
    if (label.isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _tagFailed = false;
    });
    final result = await ref.read(createTagProvider)(label);
    if (!mounted) return;
    final tag = result.valueOrNull;
    setState(() {
      _creating = false;
      if (tag == null) {
        _tagFailed = true;
      } else {
        _created.add(tag);
        _tags = {...?_tags, tag.id};
        _newTag.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(seriesDetailProvider(widget.seriesId)).value;
    final lookups = ref.watch(detailLookupsProvider);
    if (state is! DetailData) return const SizedBox.shrink();
    final detail = state.snapshot.detail;
    final theme = Theme.of(context);

    if (lookups.isLoading) {
      return Center(
        child: BusyIndicator(
          semanticLabel: context.l10n.commonLoading,
          size: 36,
          strokeWidth: 4,
        ),
      );
    }
    final failure = lookups.error;
    if (failure != null) {
      final copy = failure is AppError
          ? connectionErrorMessage(l10n, failure, kind: ServiceKind.sonarr)
          : null;
      return ErrorState(
        headline: l10n.sonarrDetailEditOptionsFailed,
        message: copy?.message ?? '',
        hint: copy?.hint,
        retryLabel: l10n.sonarrRetry,
        onRetry: () => ref.invalidate(detailLookupsProvider),
      );
    }
    final options = lookups.value!;
    final monitored = _monitored ?? detail.summary.monitored;
    final profile = _profile ?? detail.summary.qualityProfileId;
    final selectedTags = _tags ?? detail.summary.tags.toSet();
    final allTags = [
      for (final t in options.tags) t,
      for (final c in _created)
        if (!options.tags.any((t) => t.id == c.id)) c,
    ];
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(ConsolarrSpacing.lg),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.sonarrDetailEditMonitored),
          value: monitored,
          onChanged: (v) => setState(() => _monitored = v),
        ),
        const SizedBox(height: ConsolarrSpacing.md),
        DetailSheetHeading(l10n.sonarrDetailEditProfile),
        Wrap(
          spacing: ConsolarrSpacing.sm,
          runSpacing: ConsolarrSpacing.sm,
          children: [
            for (final p in options.profiles)
              ChoiceChip(
                label: Text(p.name),
                selected: p.id == profile,
                onSelected: (_) => setState(() => _profile = p.id),
              ),
          ],
        ),
        const SizedBox(height: ConsolarrSpacing.lg),
        DetailSheetHeading(l10n.sonarrDetailEditTags),
        if (allTags.isEmpty)
          Text(l10n.sonarrDetailEditNoTags)
        else
          Wrap(
            spacing: ConsolarrSpacing.sm,
            runSpacing: ConsolarrSpacing.sm,
            children: [
              for (final t in allTags)
                FilterChip(
                  label: Text(t.label),
                  selected: selectedTags.contains(t.id),
                  onSelected: (on) => setState(() {
                    final next = {...selectedTags};
                    on ? next.add(t.id) : next.remove(t.id);
                    _tags = next;
                  }),
                ),
            ],
          ),
        const SizedBox(height: ConsolarrSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _newTag,
                maxLength: 64,
                decoration: InputDecoration(
                  labelText: l10n.sonarrDetailEditNewTag,
                  errorText: _tagFailed ? l10n.sonarrDetailEditTagFailed : null,
                  counterText: '',
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: ConsolarrSpacing.sm),
            TextButton(
              onPressed: _creating ? null : _addTag,
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  ConsolarrSpacing.minTapTarget,
                  ConsolarrSpacing.minTapTarget,
                ),
              ),
              child: Text(l10n.sonarrDetailEditAddTag),
            ),
          ],
        ),
        const SizedBox(height: ConsolarrSpacing.xl),
        if (_save == _Save.failed)
          Padding(
            padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.sonarrDetailEditFailed,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.roles.error,
                ),
              ),
            ),
          ),
        FilledButton(
          onPressed: _save == _Save.saving ? null : () => _submit(state),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ConsolarrSpacing.minTapTarget),
          ),
          child: Text(
            _save == _Save.saving
                ? l10n.sonarrDetailEditSaving
                : l10n.sonarrDetailEditSave,
          ),
        ),
      ],
    );
  }
}

class DetailSheetHeading extends StatelessWidget {
  const DetailSheetHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
