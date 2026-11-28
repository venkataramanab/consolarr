// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// A partial failure inside a working screen: a warning icon, what could not
/// be read, and a retry button. The rest of the screen stays usable. The
/// caller supplies the (localized) texts and what a retry does.
class InlineRetryRow extends StatelessWidget {
  const InlineRetryRow({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    super.key,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
      child: Semantics(
        container: true,
        child: Row(
          children: [
            const Icon(Icons.warning_amber_outlined),
            const SizedBox(width: ConsolarrSpacing.sm),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
