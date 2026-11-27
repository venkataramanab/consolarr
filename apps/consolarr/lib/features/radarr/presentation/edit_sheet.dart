// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/stand_ins/glass_sheet.dart';
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
    builder: (_) => EditMovieForm(movie: movie),
  );
}

class EditMovieForm extends ConsumerStatefulWidget {
  const EditMovieForm({required this.movie, super.key});

  final RadarrMovie movie;

  @override
  ConsumerState<EditMovieForm> createState() => _EditMovieFormState();
}

class _EditMovieFormState extends ConsumerState<EditMovieForm> {
  late bool _monitored = widget.movie.monitored;
  late int? _profile = widget.movie.qualityProfileId;
  late MinimumAvailability _min =
      widget.movie.minimumAvailability == MinimumAvailability.unknown
      ? MinimumAvailability.released
      : widget.movie.minimumAvailability;
  late Set<int> _tags = {...widget.movie.tags};
  bool _saving = false;
  AppError? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await ref
        .read(movieDetailProvider(widget.movie.id).notifier)
        .save(
          monitored: _monitored,
          qualityProfileId: _profile,
          minimumAvailability: _min,
          tags: _tags.toList()..sort(),
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
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
    final profiles = ref.watch(qualityProfilesProvider).value ?? const [];
    final tags = ref.watch(tagsProvider).value ?? const [];
    final knownProfile = profiles.any((p) => p.id == _profile);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.lg,
      ),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.radarrMonitored),
          value: _monitored,
          onChanged: _saving ? null : (v) => setState(() => _monitored = v),
        ),
        if (profiles.isNotEmpty)
          DropdownButtonFormField<int>(
            initialValue: knownProfile ? _profile : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.radarrQualityProfile),
            items: [
              for (final p in profiles)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: _saving ? null : (v) => setState(() => _profile = v),
          ),
        const SizedBox(height: ConsolarrSpacing.md),
        DropdownButtonFormField<MinimumAvailability>(
          initialValue: _min,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.radarrMinimumAvailability,
          ),
          items: [
            for (final m in MinimumAvailability.values)
              if (m != MinimumAvailability.unknown)
                DropdownMenuItem(
                  value: m,
                  child: Text(minimumAvailabilityText(l10n, m)),
                ),
          ],
          onChanged: _saving ? null : (v) => setState(() => _min = v ?? _min),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: ConsolarrSpacing.md),
          Text(l10n.radarrTags, style: Theme.of(context).textTheme.titleSmall),
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
                '${connectionErrorMessage(l10n, _error!).message}',
                style: TextStyle(color: context.roles.error),
              ),
            ),
          ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? l10n.radarrSaving : l10n.radarrSave),
        ),
      ],
    );
  }
}
