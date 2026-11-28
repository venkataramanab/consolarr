// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// What a user-started services check found for one server. Closed values
/// only (no name, host or id leaves the app in the bundle).
class ServerCheckResult {
  const ServerCheckResult(this.health, {this.majorVersion});

  final ServerHealth health;
  final int? majorVersion;
}

enum ServicesCheckPhase { notChecked, checking, done, failed }

class ServicesCheckState {
  const ServicesCheckState({
    this.phase = ServicesCheckPhase.notChecked,
    this.results = const {},
  });

  final ServicesCheckPhase phase;

  /// By server id; only for servers that have been checked.
  final Map<String, ServerCheckResult> results;
}

/// The "Check services" action of the diagnostics preview. Building the
/// bundle never starts a check: only [check] (a tap) does, and then it uses
/// the same probe as the server list's health.
class ServicesCheckNotifier extends Notifier<ServicesCheckState> {
  int _generation = 0;

  @override
  ServicesCheckState build() {
    _generation++;
    return const ServicesCheckState();
  }

  Future<void> check() async {
    if (state.phase == ServicesCheckPhase.checking) return;
    final generation = ++_generation;
    state = const ServicesCheckState(phase: ServicesCheckPhase.checking);
    try {
      final servers = await ref.read(serversProvider.future);
      if (!ref.mounted || generation != _generation) return;
      final repo = ref.read(serverRepositoryProvider);
      final tester = ref.read(healthTesterProvider);
      final results = <String, ServerCheckResult>{};
      await Future.wait([
        for (final s in servers)
          () async {
            final r = await _one(s, repo, tester);
            if (!ref.mounted || generation != _generation) return;
            results[s.profile.id] = r;
            // Publish as results arrive: each kind leaves "checking" on its own.
            state = ServicesCheckState(
              phase: ServicesCheckPhase.checking,
              results: Map.of(results),
            );
          }(),
      ]);
      if (!ref.mounted || generation != _generation) return;
      state = ServicesCheckState(
        phase: ServicesCheckPhase.done,
        results: Map.of(results),
      );
    } on Object {
      if (!ref.mounted || generation != _generation) return;
      state = const ServicesCheckState(phase: ServicesCheckPhase.failed);
    }
  }

  Future<ServerCheckResult> _one(
    ServerEntry s,
    ServerRepository repo,
    ConnectionTester tester,
  ) async {
    if (s.needsCredentials) {
      return const ServerCheckResult(ServerHealth.unauthorized);
    }
    try {
      final credentials = await repo.loadCredentials(s.profile);
      final outcome = await tester.test(s.profile, credentials);
      return ServerCheckResult(
        healthFromOutcome(outcome),
        majorVersion: outcome is ConnectionTestSuccess
            ? outcome.majorVersion
            : null,
      );
    } on Object {
      return const ServerCheckResult(ServerHealth.unreachable);
    }
  }
}

final servicesCheckProvider =
    NotifierProvider.autoDispose<ServicesCheckNotifier, ServicesCheckState>(
      ServicesCheckNotifier.new,
    );

/// One entry per kind that has servers, from the stored list and the check
/// state. Pure: it starts nothing. [known] holds health that was already
/// resolved elsewhere (the server list), which counts as checked.
List<DiagnosticsServiceEntry> serviceEntries(
  List<ServerEntry> servers,
  ServicesCheckState check, {
  Map<String, ServerHealth> known = const {},
}) {
  final entries = <DiagnosticsServiceEntry>[];
  for (final kind in ServiceKind.values) {
    final param = ServiceKindParam.fromCode(kind.name);
    final ofKind = [
      for (final s in servers)
        if (s.profile.kind == kind) s,
    ];
    if (param == null || ofKind.isEmpty) continue;
    final healths = <ServiceHealthBucket>[];
    int? major;
    for (final s in ofKind) {
      final id = s.profile.id;
      final r = check.results[id];
      final health = r?.health ?? known[id];
      healths.add(
        health == null
            ? (check.phase == ServicesCheckPhase.checking
                  ? ServiceHealthBucket.checking
                  : ServiceHealthBucket.notChecked)
            : _bucket(health),
      );
      final m = r?.majorVersion;
      if (m != null && (major == null || m > major)) major = m;
    }
    entries.add(
      DiagnosticsServiceEntry(
        kind: param,
        servers: ofKind.length,
        health: _combine(healths),
        majorVersion: major,
        cleartextOptIn: ofKind.any((s) => s.profile.allowCleartext),
      ),
    );
  }
  return entries;
}

ServiceHealthBucket _bucket(ServerHealth h) => switch (h) {
  ServerHealth.checking => ServiceHealthBucket.checking,
  ServerHealth.healthy => ServiceHealthBucket.healthy,
  ServerHealth.degraded => ServiceHealthBucket.degraded,
  ServerHealth.unauthorized => ServiceHealthBucket.unauthorized,
  ServerHealth.unreachable => ServiceHealthBucket.unreachable,
};

/// The worst bucket wins; a mix of checked and unchecked is "partial".
ServiceHealthBucket _combine(List<ServiceHealthBucket> all) {
  if (all.every((b) => b == ServiceHealthBucket.notChecked)) {
    return ServiceHealthBucket.notChecked;
  }
  if (all.contains(ServiceHealthBucket.checking)) {
    return ServiceHealthBucket.checking;
  }
  if (all.contains(ServiceHealthBucket.notChecked)) {
    return ServiceHealthBucket.partial;
  }
  for (final worst in [
    ServiceHealthBucket.unreachable,
    ServiceHealthBucket.unauthorized,
    ServiceHealthBucket.degraded,
  ]) {
    if (all.contains(worst)) return worst;
  }
  return ServiceHealthBucket.healthy;
}
