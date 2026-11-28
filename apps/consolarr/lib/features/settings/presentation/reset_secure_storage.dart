// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a destructive confirmation and only then clears the secure
/// storage. Cancelling (or dismissing) changes nothing. Returns whether the
/// storage was reset.
Future<bool> confirmAndResetSecureStorage(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(l10n.resetStorageConfirmTitle),
      content: Text(l10n.resetStorageConfirmBody),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsCancel),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.resetStorageConfirmAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  var ok = true;
  try {
    await ref.read(secureStorageResetProvider).reset();
  } on Object {
    ok = false;
  }
  ref.invalidate(secretStoreReadableProvider);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(ok ? l10n.resetStorageDone : l10n.resetStorageFailed),
    ),
  );
  return ok;
}

/// The error state shown when the device keystore cannot be read: says what
/// happened and offers the reset (which still asks for confirmation).
class SecureStorageUnavailableBanner extends ConsumerWidget {
  const SecureStorageUnavailableBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readable = ref.watch(secretStoreReadableProvider).value ?? true;
    if (readable) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
      child: Semantics(
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.error),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(ConsolarrSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, color: theme.colorScheme.error),
                    const SizedBox(width: ConsolarrSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.resetStorageBannerTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ConsolarrSpacing.sm),
                Text(l10n.resetStorageBannerMessage),
                const SizedBox(height: ConsolarrSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => confirmAndResetSecureStorage(context, ref),
                    child: Text(l10n.resetStorageBannerAction),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
