// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/connection_tester.dart';
import 'package:consolarr/features/servers/data/drift_server_repository.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// Server profiles and their secrets. Lazy: nothing opens before first use.
final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  final tracker = ref.watch(eventTrackerProvider);
  return DriftServerRepository(
    db: ref.watch(databaseProvider),
    secrets: ref.watch(secretStoreProvider),
    cache: ref.watch(payloadCacheProvider),
    onServerAdded: (profile) {
      final kind = ServiceKindParam.fromCode(profile.kind.name);
      if (kind != null) tracker.track(ServerAddedEvent(serviceKind: kind));
    },
  );
});

/// All servers in the user's order (SRV-01).
final serversProvider = StreamProvider<List<ServerEntry>>(
  (ref) => ref.watch(serverRepositoryProvider).watchAll(),
);

/// Runs the status/version query without reporting anything (health checks).
final healthTesterProvider = Provider<ConnectionTester>(
  (ref) => DefaultConnectionTester(
    ref.watch(secureHttpClientFactoryProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// The tester for the editor and onboarding: reports `connection_test_result`.
final connectionTesterProvider = Provider<ConnectionTester>(
  (ref) => TrackedConnectionTester(
    ref.watch(healthTesterProvider),
    ref.watch(eventTrackerProvider),
  ),
);

/// Maps a test outcome to the health shown in the list (SRV-10).
ServerHealth healthFromOutcome(ConnectionTestOutcome outcome) =>
    switch (outcome) {
      ConnectionTestSuccess() => ServerHealth.healthy,
      ConnectionTestFailure(:final error) => switch (error.category) {
        ErrorCategory.authFailed => ServerHealth.unauthorized,
        ErrorCategory.timeout ||
        ErrorCategory.serverError ||
        ErrorCategory.parseError => ServerHealth.degraded,
        _ => ServerHealth.unreachable,
      },
    };

/// Health of one server. While loading it is "checking"; pull to recheck with
/// `ref.invalidate(serverHealthProvider(id))`.
final serverHealthProvider = FutureProvider.autoDispose
    .family<ServerHealth, String>((ref, id) async {
      final repo = ref.watch(serverRepositoryProvider);
      final entry = await repo.find(id);
      if (entry == null) return ServerHealth.unreachable;
      if (entry.needsCredentials) return ServerHealth.unauthorized;
      final credentials = await repo.loadCredentials(entry.profile);
      final outcome = await ref
          .watch(healthTesterProvider)
          .test(entry.profile, credentials);
      return healthFromOutcome(outcome);
    });
