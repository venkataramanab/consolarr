// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:material_ui/material_ui.dart';

class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(ConsolarrSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight
                ? (constraints.maxHeight - 2 * ConsolarrSpacing.xl).clamp(
                    0,
                    double.infinity,
                  )
                : 0,
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// Soft icon, short headline, context-aware hint and a primary action.
///
/// Used for "nothing yet", "filters hide everything" and "all good".
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.headline,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String headline;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    return _CenteredScroll(
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 56, color: roles.textTertiary),
        ),
        const SizedBox(height: ConsolarrSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: ConsolarrSpacing.sm),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: ConsolarrSpacing.xl),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
  }
}

/// Names the cause and the likely fix, with retry.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.headline,
    required this.message,
    this.hint,
    this.icon = Icons.error_outline,
    this.retryLabel,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String headline;

  /// The cause, in plain language.
  final String message;

  /// The likely fix.
  final String? hint;
  final IconData icon;
  final String? retryLabel;
  final VoidCallback? onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    return _CenteredScroll(
      children: [
        ExcludeSemantics(child: Icon(icon, size: 56, color: roles.error)),
        const SizedBox(height: ConsolarrSpacing.lg),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (hint != null) ...[
          const SizedBox(height: ConsolarrSpacing.sm),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (retryLabel != null && onRetry != null) ...[
          const SizedBox(height: ConsolarrSpacing.xl),
          FilledButton(onPressed: onRetry, child: Text(retryLabel!)),
        ],
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(height: ConsolarrSpacing.sm),
          TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
        ],
      ],
    );
  }
}

/// Shows that content is a cached copy, with its age. Write actions elsewhere
/// are disabled and explained by the screen.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    required this.message,
    this.ageText,
    this.retryLabel,
    this.onRetry,
    super.key,
  });

  final String message;

  /// Already localized age, for example "Updated 5 minutes ago".
  final String? ageText;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: roles.raised,
          borderRadius: ConsolarrRadii.card,
          border: Border.all(color: roles.warning),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ConsolarrSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(Icons.cloud_off_outlined, color: roles.warning),
              ),
              const SizedBox(width: ConsolarrSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: theme.textTheme.labelLarge),
                    if (ageText != null)
                      Text(ageText!, style: theme.textTheme.bodyMedium),
                    if (retryLabel != null && onRetry != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: ConsolarrSpacing.xs,
                        ),
                        child: TextButton(
                          onPressed: onRetry,
                          child: Text(retryLabel!),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
