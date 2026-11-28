// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/app_info.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/services_check.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/external_actions.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// What the diagnostics screen shows of the in-app log: the state plus a lazy
/// window onto the circular buffer. Rows are read with [entryAt] while the
/// view is current; nothing is copied when a line is added.
@immutable
class DiagnosticsLogView {
  const DiagnosticsLogView({
    required this.log,
    required this.enabled,
    required this.level,
    required this.version,
    required this.length,
  });

  final DiagnosticsLog log;
  final bool enabled;
  final LogLevel level;

  /// Changes with every added or removed line.
  final int version;

  /// Number of stored lines.
  final int length;

  bool get isEmpty => length == 0;

  /// The line at [index], 0 being the oldest.
  LogEntry entryAt(int index) => log.entryAt(index);

  @override
  bool operator ==(Object other) =>
      other is DiagnosticsLogView &&
      identical(other.log, log) &&
      other.version == version &&
      other.enabled == enabled &&
      other.level == level;

  @override
  int get hashCode => Object.hash(log, version, enabled, level);
}

/// Mirrors [DiagnosticsLog] for widgets (it is a plain Dart object). It
/// auto-disposes, so nothing listens (or rebuilds) while the screen is closed.
class DiagnosticsLogNotifier extends Notifier<DiagnosticsLogView> {
  @override
  DiagnosticsLogView build() {
    final log = ref.watch(diagnosticsLogProvider);
    void listener() => state = _view(log);
    log.addListener(listener);
    ref.onDispose(() => log.removeListener(listener));
    return _view(log);
  }

  DiagnosticsLogView _view(DiagnosticsLog log) => DiagnosticsLogView(
    log: log,
    enabled: log.enabled,
    level: log.level,
    version: log.version,
    length: log.length,
  );

  void clear() => ref.read(diagnosticsLogProvider).clear();
}

final diagnosticsLogViewProvider =
    NotifierProvider.autoDispose<DiagnosticsLogNotifier, DiagnosticsLogView>(
      DiagnosticsLogNotifier.new,
    );

/// API error categories seen so far, from the breadcrumb trail (closed set;
/// newest last, no repeats).
List<String> errorCategoriesFrom(Breadcrumbs crumbs) {
  final seen = <String>[];
  for (final c in crumbs.entries) {
    final parts = c.line.split(' ');
    if (parts.length >= 2 && parts.first == 'api_error') {
      if (!seen.contains(parts[1])) seen.add(parts[1]);
    }
  }
  return seen;
}

/// The redacted bundle shown in the preview and shared byte for byte. Built
/// on demand; known values (server names, hosts, user names) are scrubbed on
/// top of the pattern rules.
///
/// A services-check result changes only the Services section: [build] does not
/// watch the check, it listens to it and swaps that one section
/// ([DiagnosticsBundle.withServices]), so the credentials, the platform
/// description and the log lines are not read or scrubbed again.
class DiagnosticsBundleNotifier extends AsyncNotifier<DiagnosticsBundle> {
  @override
  Future<DiagnosticsBundle> build() async {
    final settings = ref.watch(settingsProvider);
    // The known values (server names, hosts, user names) are scrubbed on top
    // of the pattern rules, so the bundle is never built without them: while
    // the list loads this waits, and if it fails the bundle fails (the screen
    // shows the error state) instead of being built unscrubbed.
    final servers = await ref.watch(serversProvider.future);
    final repo = ref.watch(serverRepositoryProvider);
    final known = <String>[];
    for (final s in servers) {
      known
        ..add(s.profile.name)
        ..add(s.profile.address.host);
      final alt = s.profile.alternateAddress;
      if (alt != null) known.add(alt.host);
      // The path prefix is part of the address (`/sonarr`, `/media/tv`).
      if (s.profile.pathPrefix.isNotEmpty) known.add(s.profile.pathPrefix);
      final creds = await repo.loadCredentials(s.profile);
      known
        ..addAll([?creds.username, ?creds.password, ?creds.apiKey])
        // Custom header values are secrets too (names are not).
        ..addAll(creds.headers.map((h) => h.value));
    }
    // Health that is already resolved (the server list) counts; nothing is
    // started here: a check runs only on the user's tap.
    final resolved = <String, ServerHealth>{};
    for (final s in servers) {
      final provider = serverHealthProvider(s.profile.id);
      if (ref.read(provider.exists)) {
        final h = ref.read(provider).asData?.value;
        if (h != null && h != ServerHealth.checking) {
          resolved[s.profile.id] = h;
        }
      }
    }
    final consent = ref.watch(consentProvider);
    final flavor = ref.watch(telemetryAvailableProvider)
        ? AppFlavor.play
        : AppFlavor.foss;
    final platform = await ref
        .watch(externalActionsProvider)
        .platformDescription();
    final info = DiagnosticsInfo(
      appVersion: '$appVersion+$appBuild',
      buildMode: kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      platform: platform,
      locale:
          settings.localeTag ??
          WidgetsBinding.instance.platformDispatcher.locale.languageCode,
      flavor: flavor,
      crashReportsConsent: consent.crashReports,
      analyticsConsent: consent.analytics,
    );
    List<DiagnosticsServiceEntry> servicesFor(ServicesCheckState check) =>
        serviceEntries(servers, check, known: resolved);

    final bundle = DiagnosticsBundle.build(
      info: info,
      errorCategories: errorCategoriesFrom(ref.read(breadcrumbsProvider)),
      entries: ref.read(diagnosticsLogProvider).entries,
      services: servicesFor(ref.read(servicesCheckProvider)),
      // Preview == shared text: the bundle itself stays within the share cap.
      maxBytes: shareTextMaxBytes,
      scrubber: DiagnosticsScrubber(knownValues: known),
    );
    // Only the Services section follows the check (and only after the first
    // value exists; until then `build` has read the latest state anyway).
    ref.listen(servicesCheckProvider, (_, check) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.withServices(servicesFor(check)));
      }
    });
    return bundle;
  }
}

final diagnosticsBundleProvider =
    AsyncNotifierProvider.autoDispose<
      DiagnosticsBundleNotifier,
      DiagnosticsBundle
    >(DiagnosticsBundleNotifier.new);
