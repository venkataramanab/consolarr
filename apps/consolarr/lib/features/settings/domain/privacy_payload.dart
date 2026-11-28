// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';

/// One kind of event that anonymous usage can send, described in words. The
/// map is keyed by the event name in the event catalog; a test checks that
/// every event of the catalog has an entry (and no entry is stale), so the description cannot drift from what is sent.
final Map<String, String Function(AppLocalizations)> privacyPayloadItems = {
  'servers_screen_viewed': (l10n) => l10n.privacyEventScreenViewed,
  'servers_added': (l10n) => l10n.privacyEventServerAdded,
  'servers_connection_test_result': (l10n) => l10n.privacyEventConnectionTest,
  'servers_certificate_decision': (l10n) => l10n.privacyEventCertificate,
  'settings_app_lock_toggled': (l10n) => l10n.privacyEventAppLock,
  'settings_consent_changed': (l10n) => l10n.privacyEventConsent,
  'settings_diagnostics_shared': (l10n) => l10n.privacyEventDiagnostics,
  'sonarr_series_added': (l10n) => l10n.privacyEventSonarrSeriesAdded,
  'sonarr_release_grabbed': (l10n) => l10n.privacyEventSonarrReleaseGrabbed,
  'sonarr_search_started': (l10n) => l10n.privacyEventSonarrSearchStarted,
  'sonarr_search_finished': (l10n) => l10n.privacyEventSonarrSearchFinished,
  'sonarr_queue_item_removed': (l10n) =>
      l10n.privacyEventSonarrQueueItemRemoved,
  'sonarr_series_monitor_changed': (l10n) =>
      l10n.privacyEventSonarrMonitorChanged,
  'radarr_movie_added': (l10n) => l10n.privacyEventRadarrMovieAdded,
  'radarr_release_grabbed': (l10n) => l10n.privacyEventRadarrReleaseGrabbed,
  'radarr_search_started': (l10n) => l10n.privacyEventRadarrSearchStarted,
  'radarr_queue_item_removed': (l10n) =>
      l10n.privacyEventRadarrQueueItemRemoved,
  'torrents_added': (l10n) => l10n.privacyEventTorrentsAdded,
  'torrents_action': (l10n) => l10n.privacyEventTorrentsAction,
  'torrents_speed_limits_changed': (l10n) =>
      l10n.privacyEventTorrentsSpeedLimits,
  'dashboard_refreshed': (l10n) => l10n.privacyEventDashboardRefreshed,
  'dashboard_card_opened': (l10n) => l10n.privacyEventDashboardCardOpened,
  'dashboard_card_retried': (l10n) => l10n.privacyEventDashboardCardRetried,
  'poll_cycle_finished': (l10n) => l10n.privacyEventPollCycleFinished,
  'poll_change_detected': (l10n) => l10n.privacyEventPollChangeDetected,
};
