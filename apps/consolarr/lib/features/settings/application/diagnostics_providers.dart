// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/app_info.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// What the diagnostics screen shows of the in-app log.
@immutable
class DiagnosticsLogView {
  const DiagnosticsLogView({
    required this.enabled,
    required this.level,
    required this.entries,
  });

  final bool enabled;
  final LogLevel level;

  /// Oldest first.
  final List<LogEntry> entries;
}

/// Mirrors [DiagnosticsLog] for widgets (it is a plain Dart object).
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
    enabled: log.enabled,
    level: log.level,
    entries: log.entries,
  );

  void clear() => ref.read(diagnosticsLogProvider).clear();
}

final diagnosticsLogViewProvider =
    NotifierProvider<DiagnosticsLogNotifier, DiagnosticsLogView>(
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
final diagnosticsBundleProvider = FutureProvider.autoDispose<DiagnosticsBundle>(
  (ref) async {
    final settings = ref.watch(settingsProvider);
    final servers = ref.watch(serversProvider).value ?? const [];
    final repo = ref.watch(serverRepositoryProvider);
    final known = <String>[];
    for (final s in servers) {
      known
        ..add(s.profile.name)
        ..add(s.profile.address.host);
      final alt = s.profile.alternateAddress;
      if (alt != null) known.add(alt.host);
      final creds = await repo.loadCredentials(s.profile);
      known..addAll([?creds.username, ?creds.password, ?creds.apiKey]);
    }
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
    );
    return DiagnosticsBundle.build(
      info: info,
      errorCategories: errorCategoriesFrom(ref.read(breadcrumbsProvider)),
      entries: ref.read(diagnosticsLogProvider).entries,
      scrubber: DiagnosticsScrubber(knownValues: known),
    );
  },
);
