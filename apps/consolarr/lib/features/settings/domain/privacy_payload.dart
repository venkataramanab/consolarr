// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';

/// One kind of event that anonymous usage can send, described in words. The
/// map is keyed by the event name in the event catalog; a test checks that
/// every event of the areas this screen can describe has an entry (and no
/// entry is stale), so the description cannot drift from what is sent.
final Map<String, String Function(AppLocalizations)> privacyPayloadItems = {
  'screen_viewed': (l10n) => l10n.privacyEventScreenViewed,
  'server_added': (l10n) => l10n.privacyEventServerAdded,
  'connection_test_result': (l10n) => l10n.privacyEventConnectionTest,
  'certificate_decision': (l10n) => l10n.privacyEventCertificate,
  'app_lock_toggled': (l10n) => l10n.privacyEventAppLock,
  'consent_changed': (l10n) => l10n.privacyEventConsent,
  'diagnostics_shared': (l10n) => l10n.privacyEventDiagnostics,
};
