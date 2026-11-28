// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Quality profiles, root folders and tags as one state, for the add and edit
/// sheets: loading, the first failure (with retry), or ready.
enum OptionsLoad { loading, failed, ready }

/// Combined load state of the shared lists in [watched].
(OptionsLoad, AppError?) optionsLoad(List<AsyncValue<Object?>> watched) {
  for (final v in watched) {
    if (v.isLoading) return (OptionsLoad.loading, null);
  }
  for (final v in watched) {
    if (v.hasError) {
      final e = v.error;
      return (
        OptionsLoad.failed,
        e is AppError ? e : const AppError(ErrorCategory.parseError),
      );
    }
  }
  return (OptionsLoad.ready, null);
}

/// Reloads the three shared lists.
void retryOptions(WidgetRef ref) {
  ref
    ..invalidate(qualityProfilesProvider)
    ..invalidate(rootFoldersProvider)
    ..invalidate(tagsProvider);
}

/// Placeholder while the lists load.
class OptionsLoading extends StatelessWidget {
  const OptionsLoading({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.radarrOptionsLoading,
    liveRegion: true,
    child: const ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.all(ConsolarrSpacing.gutter),
        child: SkeletonBox(height: 240, borderRadius: ConsolarrRadii.card),
      ),
    ),
  );
}

/// Failure of the lists, with a retry. Never an empty picker.
class OptionsError extends StatelessWidget {
  const OptionsError({required this.error, required this.onRetry, super.key});

  final AppError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final copy = connectionErrorMessage(l10n, error, kind: ServiceKind.radarr);
    return ErrorState(
      headline: l10n.radarrOptionsErrorHeadline,
      message: copy.message,
      hint: copy.hint,
      retryLabel: l10n.radarrRetry,
      onRetry: onRetry,
    );
  }
}
