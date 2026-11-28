// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/add_options_form.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/options_state.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the edit sheet (RAD-09): monitored, quality profile, minimum
/// availability and tags. The folder is not editable here.
Future<void> showEditSheet(BuildContext context, RadarrMovie movie) {
  final l10n = context.l10n;
  return showGlassSheet<void>(
    context: context,
    title: l10n.radarrEditTitle,
    closeLabel: l10n.radarrClose,
    detents: GlassSheetDetents.full,
    // The sheet paints its own surface: tiles need a Material of their own.
    scrollBuilder: (context, controller) => Material(
      type: MaterialType.transparency,
      child: EditMovieForm(movie: movie, controller: controller),
    ),
  );
}

class EditMovieForm extends ConsumerStatefulWidget {
  const EditMovieForm({required this.movie, this.controller, super.key});

  final RadarrMovie movie;
  final ScrollController? controller;

  @override
  ConsumerState<EditMovieForm> createState() => _EditMovieFormState();
}

class _EditMovieFormState extends ConsumerState<EditMovieForm> {
  late bool _monitored = widget.movie.monitored;
  late int? _profile = widget.movie.qualityProfileId;

  /// Null while the server value is one this app does not know: that stays
  /// "unchanged" and is never replaced by a guess.
  late MinimumAvailability? _min =
      widget.movie.minimumAvailability == MinimumAvailability.unknown
      ? null
      : widget.movie.minimumAvailability;
  late final Set<int> _tags = {...widget.movie.tags};
  bool _saving = false;
  AppError? _error;

  bool get _monitoredChanged => _monitored != widget.movie.monitored;
  bool get _profileChanged =>
      _profile != null && _profile != widget.movie.qualityProfileId;
  bool get _minChanged =>
      _min != null && _min != widget.movie.minimumAvailability;
  bool get _tagsChanged {
    final before = {...widget.movie.tags};
    return before.length != _tags.length || !before.containsAll(_tags);
  }

  bool get _changed =>
      _monitoredChanged || _profileChanged || _minChanged || _tagsChanged;

  Future<void> _save() async {
    // Nothing changed: nothing is sent. A second tap while saving is ignored.
    if (_saving || !_changed) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final error = await ref
        .read(movieDetailProvider(widget.movie.id).notifier)
        .save(
          monitored: _monitoredChanged ? _monitored : null,
          qualityProfileId: _profileChanged ? _profile : null,
          minimumAvailability: _minChanged ? _min : null,
          tags: _tagsChanged ? (_tags.toList()..sort()) : null,
        );
    if (!mounted) return;
    if (error == null) {
      navigator.pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profilesAsync = ref.watch(qualityProfilesProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final (load, loadError) = optionsLoad([profilesAsync, tagsAsync]);
    if (load == OptionsLoad.loading) return const OptionsLoading();
    if (load == OptionsLoad.failed) {
      return OptionsError(error: loadError!, onRetry: () => retryOptions(ref));
    }
    final profiles = profilesAsync.value ?? const <ArrQualityProfile>[];
    final tags = tagsAsync.value ?? const <ArrTag>[];
    final knownProfile = profiles.any((p) => p.id == _profile);
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.lg,
      ),
      children: [
        ArrOptionSwitch(
          title: l10n.radarrMonitored,
          value: _monitored,
          onChanged: (v) {
            if (!_saving) setState(() => _monitored = v);
          },
        ),
        if (profiles.isNotEmpty)
          ArrOptionPicker<int>(
            label: l10n.radarrQualityProfile,
            value: knownProfile ? _profile : null,
            options: [for (final p in profiles) ArrOption(p.id, p.name)],
            onChanged: (v) {
              if (!_saving) setState(() => _profile = v);
            },
          ),
        ArrOptionPicker<MinimumAvailability>(
          label: l10n.radarrMinimumAvailability,
          value: _min,
          options: [
            for (final m in MinimumAvailability.values)
              if (m != MinimumAvailability.unknown)
                ArrOption(m, minimumAvailabilityText(l10n, m)),
          ],
          onChanged: (v) {
            if (!_saving) setState(() => _min = v);
          },
        ),
        if (tags.isNotEmpty) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                l10n.radarrTags,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: context.roles.textPrimary),
              ),
            ),
          ),
          Wrap(
            spacing: ConsolarrSpacing.sm,
            children: [
              for (final t in tags)
                FilterChip(
                  label: Text(t.label),
                  selected: _tags.contains(t.id),
                  onSelected: _saving
                      ? null
                      : (on) => setState(
                          () => on ? _tags.add(t.id) : _tags.remove(t.id),
                        ),
                ),
            ],
          ),
        ],
        const SizedBox(height: ConsolarrSpacing.md),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
              child: Text(
                '${l10n.radarrSaveFailed} '
                '${connectionErrorMessage(l10n, _error!, kind: ServiceKind.radarr).message}',
                style: TextStyle(color: context.roles.error),
              ),
            ),
          ),
        FilledButton(
          onPressed: _saving || !_changed ? null : _save,
          child: Text(_saving ? l10n.radarrSaving : l10n.radarrSave),
        ),
      ],
    );
  }
}
