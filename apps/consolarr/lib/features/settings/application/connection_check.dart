// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The steps of the connection check, in order (SET-05).
enum CheckStep { dns, connect, tls, auth, version }

enum CheckStepState { pending, running, pass, fail, skipped, notNeeded }

/// Which step an [ErrorCategory] belongs to. Every category maps to exactly
/// one step; a test covers all of them.
CheckStep stepForCategory(ErrorCategory category) => switch (category) {
  ErrorCategory.networkUnreachable ||
  ErrorCategory.timeout => CheckStep.connect,
  ErrorCategory.tlsUntrusted ||
  ErrorCategory.tlsExpired ||
  ErrorCategory.tlsPinMismatch ||
  ErrorCategory.cleartextRefused => CheckStep.tls,
  ErrorCategory.authFailed => CheckStep.auth,
  ErrorCategory.unsupportedVersion ||
  ErrorCategory.notFound ||
  ErrorCategory.serverError ||
  ErrorCategory.parseError ||
  ErrorCategory.redirectRefused ||
  ErrorCategory.responseTooLarge ||
  ErrorCategory.requestTooLarge => CheckStep.version,
};

/// The result of one step. A failed step carries either an [error] (from the
/// connection tester) or a [localFailure] (name resolution and connect
/// probes, which have no `AppError`).
class StepResult {
  const StepResult(this.step, this.state, {this.error, this.localFailure});

  final CheckStep step;
  final CheckStepState state;
  final AppError? error;
  final CheckStep? localFailure;

  StepResult withState(CheckStepState s) => StepResult(step, s);
}

class ConnectionCheckResult {
  const ConnectionCheckResult(
    this.steps, {
    this.version,
    this.finished = false,
  });

  /// All five steps, in order.
  final List<StepResult> steps;

  /// Version reported by a server that passed every step.
  final String? version;
  final bool finished;

  static ConnectionCheckResult pending() => ConnectionCheckResult([
    for (final s in CheckStep.values) StepResult(s, CheckStepState.pending),
  ]);

  /// The result for a server whose saved credentials are missing: nothing is
  /// sent, the sign-in step says so and the rest is skipped.
  static ConnectionCheckResult needsCredentials({bool apiKey = false}) =>
      ConnectionCheckResult([
        const StepResult(CheckStep.dns, CheckStepState.skipped),
        const StepResult(CheckStep.connect, CheckStepState.skipped),
        const StepResult(CheckStep.tls, CheckStepState.skipped),
        StepResult(
          CheckStep.auth,
          CheckStepState.fail,
          error: AppError(
            ErrorCategory.authFailed,
            debugDetail: apiKey ? needsApiKeyDetail : needsCredentialsDetail,
          ),
        ),
        const StepResult(CheckStep.version, CheckStepState.skipped),
      ], finished: true);

  StepResult? get failed {
    for (final s in steps) {
      if (s.state == CheckStepState.fail) return s;
    }
    return null;
  }

  bool get allPassed =>
      finished &&
      steps.every(
        (s) =>
            s.state == CheckStepState.pass ||
            s.state == CheckStepState.notNeeded,
      );
}

/// Name resolution and TCP connect against the user's own saved server. They
/// send **no bytes**.
abstract interface class NetworkProbe {
  Future<bool> resolves(String host);
  Future<bool> connects(String host, int port);
}

class DartIoNetworkProbe implements NetworkProbe {
  const DartIoNetworkProbe({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  @override
  Future<bool> resolves(String host) async {
    try {
      final found = await InternetAddress.lookup(host).timeout(timeout);
      return found.isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> connects(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }
}

/// Runs the check. Everything from TLS onwards goes through the existing
/// per-kind connection tester (and so through the secure client factory); no
/// new endpoint knowledge lives here.
class ConnectionCheck {
  ConnectionCheck({required this.probe, required this.tester});

  final NetworkProbe probe;
  final ConnectionTester tester;

  Stream<ConnectionCheckResult> run(
    ServerProfile profile,
    ServerCredentials credentials,
  ) async* {
    var steps = ConnectionCheckResult.pending().steps;
    ConnectionCheckResult emit({String? version, bool finished = false}) =>
        ConnectionCheckResult(
          List.unmodifiable(steps),
          version: version,
          finished: finished,
        );
    void set(CheckStep step, StepResult result) {
      steps = [for (final s in steps) s.step == step ? result : s];
    }

    void skipAfter(CheckStep step) {
      steps = [
        for (final s in steps)
          s.step.index > step.index ? s.withState(CheckStepState.skipped) : s,
      ];
    }

    final host = profile.address.host;
    final port = profile.address.hasPort
        ? profile.address.port
        : (profile.isSecure ? 443 : 80);

    // 1. Name resolution (an address literal needs no lookup).
    set(CheckStep.dns, const StepResult(CheckStep.dns, CheckStepState.running));
    yield emit();
    final literal = InternetAddress.tryParse(host) != null;
    if (!literal && !await probe.resolves(host)) {
      set(
        CheckStep.dns,
        const StepResult(
          CheckStep.dns,
          CheckStepState.fail,
          localFailure: CheckStep.dns,
        ),
      );
      skipAfter(CheckStep.dns);
      yield emit(finished: true);
      return;
    }
    set(CheckStep.dns, const StepResult(CheckStep.dns, CheckStepState.pass));

    // 2. Connect.
    set(
      CheckStep.connect,
      const StepResult(CheckStep.connect, CheckStepState.running),
    );
    yield emit();
    if (!await probe.connects(host, port)) {
      set(
        CheckStep.connect,
        const StepResult(
          CheckStep.connect,
          CheckStepState.fail,
          localFailure: CheckStep.connect,
        ),
      );
      skipAfter(CheckStep.connect);
      yield emit(finished: true);
      return;
    }
    set(
      CheckStep.connect,
      const StepResult(CheckStep.connect, CheckStepState.pass),
    );

    // 3-5. TLS, sign-in and API version in one request through the secure
    // client; the error category says which step failed.
    set(CheckStep.tls, const StepResult(CheckStep.tls, CheckStepState.running));
    yield emit();
    final outcome = await tester.test(profile, credentials);
    switch (outcome) {
      case ConnectionTestSuccess(:final version):
        set(
          CheckStep.tls,
          StepResult(
            CheckStep.tls,
            profile.isSecure ? CheckStepState.pass : CheckStepState.notNeeded,
          ),
        );
        set(
          CheckStep.auth,
          const StepResult(CheckStep.auth, CheckStepState.pass),
        );
        set(
          CheckStep.version,
          const StepResult(CheckStep.version, CheckStepState.pass),
        );
        yield emit(version: version, finished: true);
      case ConnectionTestFailure(:final error):
        final failing = stepForCategory(error.category);
        for (final s in CheckStep.values) {
          if (s.index <= CheckStep.connect.index) continue;
          if (s.index < failing.index) {
            set(
              s,
              StepResult(
                s,
                s == CheckStep.tls && !profile.isSecure
                    ? CheckStepState.notNeeded
                    : CheckStepState.pass,
              ),
            );
          } else if (s == failing) {
            set(s, StepResult(s, CheckStepState.fail, error: error));
          }
        }
        skipAfter(failing);
        // A failure at connect level that only the HTTP client could see.
        if (failing == CheckStep.connect) {
          set(
            CheckStep.connect,
            StepResult(CheckStep.connect, CheckStepState.fail, error: error),
          );
        }
        yield emit(finished: true);
    }
  }
}

/// Where the check stands for the screen.
class ConnectionCheckState {
  const ConnectionCheckState({
    this.serverId,
    this.running = false,
    this.result,
    this.failed = false,
  });

  final String? serverId;
  final bool running;
  final ConnectionCheckResult? result;

  /// The run stopped because of an unexpected error (not a failed step).
  final bool failed;
}

final networkProbeProvider = Provider<NetworkProbe>(
  (ref) => const DartIoNetworkProbe(),
);

class ConnectionCheckNotifier extends Notifier<ConnectionCheckState> {
  int _generation = 0;

  @override
  ConnectionCheckState build() => const ConnectionCheckState();

  void select(String id) {
    _generation++;
    state = ConnectionCheckState(serverId: id);
  }

  /// Runs the check for [serverId] (or the chosen server).
  Future<void> run([String? serverId]) async {
    if (state.running) return;
    if (serverId != null && serverId != state.serverId) select(serverId);
    final id = state.serverId;
    if (id == null) return;
    final generation = ++_generation;
    state = ConnectionCheckState(
      serverId: id,
      running: true,
      result: ConnectionCheckResult.pending(),
    );
    try {
      final repo = ref.read(serverRepositoryProvider);
      final entry = await repo.find(id);
      if (!ref.mounted || generation != _generation) return;
      if (entry == null) {
        state = ConnectionCheckState(serverId: id);
        return;
      }
      if (entry.needsCredentials) {
        // Lost or never entered secrets: say so, send nothing.
        final stored = await repo.loadCredentials(entry.profile);
        if (!ref.mounted || generation != _generation) return;
        state = ConnectionCheckState(
          serverId: id,
          result: ConnectionCheckResult.needsCredentials(
            apiKey:
                entry.profile.kind.isArr && stored.apiKey?.isNotEmpty != true,
          ),
        );
        return;
      }
      final credentials = await repo.loadCredentials(entry.profile);
      final check = ConnectionCheck(
        probe: ref.read(networkProbeProvider),
        tester: ref.read(healthTesterProvider),
      );
      await for (final result in check.run(entry.profile, credentials)) {
        if (!ref.mounted || generation != _generation) return;
        state = ConnectionCheckState(
          serverId: id,
          running: !result.finished,
          result: result,
        );
      }
    } on Object {
      // Never stay "running": show that the check could not finish.
      if (ref.mounted && generation == _generation) {
        state = ConnectionCheckState(serverId: id, failed: true);
      }
    } finally {
      // A stream that ended without a finished result also ends the run.
      if (ref.mounted && generation == _generation && state.running) {
        state = ConnectionCheckState(
          serverId: id,
          result: state.result,
          failed: state.result?.finished != true,
        );
      }
    }
  }
}

final connectionCheckProvider =
    NotifierProvider.autoDispose<ConnectionCheckNotifier, ConnectionCheckState>(
      ConnectionCheckNotifier.new,
    );
