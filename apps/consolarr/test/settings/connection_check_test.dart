// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/features/settings/application/connection_check.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe implements NetworkProbe {
  _Probe({this.resolvesOk = true, this.connectsOk = true});

  bool resolvesOk;
  bool connectsOk;
  final List<String> resolved = [];
  final List<(String, int)> connected = [];

  @override
  Future<bool> resolves(String host) async {
    resolved.add(host);
    return resolvesOk;
  }

  @override
  Future<bool> connects(String host, int port) async {
    connected.add((host, port));
    return connectsOk;
  }
}

class _Tester implements ConnectionTester {
  _Tester(this.outcome);

  ConnectionTestOutcome outcome;
  int calls = 0;

  @override
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials credentials,
  ) async {
    calls++;
    return outcome;
  }
}

Future<ConnectionCheckResult> _run(
  _Probe probe,
  _Tester tester, {
  String address = 'https://sonarr.example',
}) async {
  final profile = ServerProfile.parse(
    id: 'a',
    name: 'Example',
    kind: ServiceKind.sonarr,
    address: address,
    authMode: AuthMode.apiKey,
  ).valueOrNull!;
  final results = await ConnectionCheck(
    probe: probe,
    tester: tester,
  ).run(profile, const ServerCredentials()).toList();
  return results.last;
}

Map<CheckStep, CheckStepState> _states(ConnectionCheckResult r) => {
  for (final s in r.steps) s.step: s.state,
};

void main() {
  test('every error category maps to exactly one step', () {
    for (final c in ErrorCategory.values) {
      expect(stepForCategory(c), isA<CheckStep>(), reason: c.code);
    }
    expect(stepForCategory(ErrorCategory.authFailed), CheckStep.auth);
    expect(stepForCategory(ErrorCategory.tlsExpired), CheckStep.tls);
    // A server that refuses a request body as too large answered at the API
    // level, like an oversized reply: it belongs to the API-version step.
    expect(stepForCategory(ErrorCategory.requestTooLarge), CheckStep.version);
    expect(stepForCategory(ErrorCategory.responseTooLarge), CheckStep.version);
    expect(
      stepForCategory(ErrorCategory.unsupportedVersion),
      CheckStep.version,
    );
  });

  test(
    'all steps pass for a healthy https server and report the version',
    () async {
      final r = await _run(
        _Probe(),
        _Tester(const ConnectionTestSuccess(version: '4.0.1', majorVersion: 4)),
      );
      expect(r.allPassed, isTrue);
      expect(r.version, '4.0.1');
      expect(_states(r).values.toSet(), {CheckStepState.pass});
    },
  );

  test('a cleartext server has no secure-connection step to pass', () async {
    final probe = _Probe();
    final r = await _run(
      probe,
      _Tester(const ConnectionTestSuccess(version: '1', majorVersion: 1)),
      address: 'http://192.0.2.10:8989',
    );
    expect(_states(r)[CheckStep.tls], CheckStepState.notNeeded);
    expect(r.allPassed, isTrue);
    expect(probe.connected.single, ('192.0.2.10', 8989));
    expect(
      probe.resolved,
      isEmpty,
      reason: 'an address literal needs no lookup',
    );
  });

  test(
    'name resolution failure skips everything after it and sends nothing',
    () async {
      final tester = _Tester(const ConnectionTestSuccess(version: '1'));
      final probe = _Probe(resolvesOk: false);
      final r = await _run(probe, tester);
      expect(r.failed!.step, CheckStep.dns);
      expect(r.failed!.localFailure, CheckStep.dns);
      expect(_states(r)[CheckStep.connect], CheckStepState.skipped);
      expect(_states(r)[CheckStep.version], CheckStepState.skipped);
      expect(probe.connected, isEmpty);
      expect(tester.calls, 0);
    },
  );

  test('connect failure stops before TLS and the request', () async {
    final tester = _Tester(const ConnectionTestSuccess(version: '1'));
    final r = await _run(_Probe(connectsOk: false), tester);
    expect(r.failed!.step, CheckStep.connect);
    expect(r.failed!.localFailure, CheckStep.connect);
    expect(_states(r)[CheckStep.dns], CheckStepState.pass);
    expect(_states(r)[CheckStep.tls], CheckStepState.skipped);
    expect(tester.calls, 0);
  });

  group('the failing step follows the error category', () {
    for (final category in ErrorCategory.values) {
      test(category.code, () async {
        final r = await _run(
          _Probe(),
          _Tester(ConnectionTestFailure(AppError(category))),
        );
        final failing = stepForCategory(category);
        final states = _states(r);
        expect(r.failed!.step, failing);
        expect(r.failed!.error!.category, category);
        for (final s in CheckStep.values) {
          if (s.index < failing.index) {
            expect(
              states[s],
              anyOf(CheckStepState.pass, CheckStepState.notNeeded),
              reason: '$s before $failing',
            );
          } else if (s.index > failing.index) {
            expect(states[s], CheckStepState.skipped, reason: '$s after');
          }
        }
        expect(r.finished, isTrue);
        expect(r.allPassed, isFalse);
      });
    }
  });

  test(
    'the first emission is all pending/running, the last is finished',
    () async {
      final profile = ServerProfile.parse(
        id: 'a',
        name: 'Example',
        kind: ServiceKind.sonarr,
        address: 'https://sonarr.example',
        authMode: AuthMode.apiKey,
      ).valueOrNull!;
      final all = await ConnectionCheck(
        probe: _Probe(),
        tester: _Tester(const ConnectionTestSuccess(version: '1')),
      ).run(profile, const ServerCredentials()).toList();
      expect(all.first.finished, isFalse);
      expect(all.first.steps.first.state, CheckStepState.running);
      expect(all.last.finished, isTrue);
      expect(all.length, greaterThan(2));
    },
  );
}
