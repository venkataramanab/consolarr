// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';
import 'package:test_harness/test_harness.dart';

ServerProfile profile(
  String id, {
  String name = 'Example Sonarr',
  ServiceKind kind = ServiceKind.sonarr,
  String address = 'https://sonarr.example',
  bool allowCleartext = false,
  AuthMode authMode = AuthMode.apiKey,
}) => ServerProfile.parse(
  id: id,
  name: name,
  kind: kind,
  address: address,
  allowCleartext: allowCleartext,
  authMode: authMode,
).valueOrNull!;

ServerEntry entry(
  String id, {
  String name = 'Example Sonarr',
  ServiceKind kind = ServiceKind.sonarr,
  String address = 'https://sonarr.example',
  bool allowCleartext = false,
  bool needsCredentials = false,
  bool isStartup = false,
  int sortOrder = 0,
  AuthMode authMode = AuthMode.apiKey,
  bool proxyLogin = false,
}) => ServerEntry(
  profile: profile(
    id,
    name: name,
    kind: kind,
    address: address,
    allowCleartext: allowCleartext,
    authMode: authMode,
  ),
  sortOrder: sortOrder,
  isStartup: isStartup,
  needsCredentials: needsCredentials,
  hasApiKey: !needsCredentials,
  proxyLogin: proxyLogin,
);

/// In-memory repository that records what the UI asked for.
class FakeServerRepository implements ServerRepository {
  FakeServerRepository([List<ServerEntry> initial = const []])
    : entries = [...initial];

  final List<ServerEntry> entries;
  final _changes = StreamController<void>.broadcast();
  final List<ServerDraft> saved = [];
  final List<String> deleted = [];
  final Map<String, ServerCredentials> credentials = {};
  int loadCredentialsCalls = 0;
  List<String>? lastOrder;
  String? startup;
  final Map<ServiceKind, String> active = {};
  AppError? saveError;
  int _revision = 0;

  @override
  Stream<List<ServerEntry>> watchAll() async* {
    yield [...entries];
    await for (final _ in _changes.stream) {
      yield [...entries];
    }
  }

  @override
  Future<ServerEntry?> find(String id) async {
    for (final e in entries) {
      if (e.profile.id == id) return e;
    }
    return null;
  }

  @override
  Future<Result<ServerEntry>> save(ServerDraft draft) async {
    saved.add(draft);
    if (saveError != null) return Result.err(saveError!);
    final parsed = ServerProfile.parse(
      id: draft.id ?? 'new',
      name: draft.name,
      kind: draft.kind,
      address: draft.address,
      pathPrefix: draft.pathPrefix,
      authMode: draft.authMode,
      allowCleartext: draft.allowCleartext,
      headerNames: [for (final h in draft.credentials.headers) h.name],
    );
    if (parsed.isErr) return Result.err(parsed.errorOrNull!);
    final e = ServerEntry(
      profile: parsed.valueOrNull!,
      sortOrder: entries.length,
    );
    entries
      ..removeWhere((x) => x.profile.id == e.profile.id)
      ..add(e);
    _revision++;
    _changes.add(null);
    return Result.ok(e);
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    entries.removeWhere((e) => e.profile.id == id);
    _changes.add(null);
  }

  @override
  Future<void> reorder(List<String> idsInOrder) async {
    lastOrder = idsInOrder;
  }

  @override
  Future<void> setStartup(String? id) async => startup = id;

  @override
  Future<void> setActive(ServiceKind kind, String id) async {
    active[kind] = id;
    _changes.add(null);
  }

  @override
  Future<String?> activeId(ServiceKind kind) async => active[kind];

  @override
  Stream<ConnectionKey> watchConnectionKey(ServiceKind kind) async* {
    Future<ConnectionKey> current() async =>
        ConnectionKey(await activeId(kind), _revision);
    var last = await current();
    yield last;
    await for (final _ in _changes.stream) {
      final next = await current();
      if (next != last) {
        last = next;
        yield next;
      }
    }
  }

  @override
  Future<ServerCredentials> loadCredentials(ServerProfile profile) async {
    loadCredentialsCalls++;
    return credentials[profile.id] ?? ServerCredentials.empty;
  }
}

/// Replays queued outcomes (the last one repeats) and records every call.
class FakeTester implements ConnectionTester {
  FakeTester([List<ConnectionTestOutcome>? outcomes])
    : outcomes = outcomes ?? [const ConnectionTestSuccess(version: '4.0.1')];

  final List<ConnectionTestOutcome> outcomes;
  final List<ServerProfile> profiles = [];
  final List<ServerCredentials> credentials = [];
  Completer<void>? gate;

  @override
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials creds,
  ) async {
    profiles.add(profile);
    credentials.add(creds);
    if (gate != null) await gate!.future;
    return outcomes.length > 1 ? outcomes.removeAt(0) : outcomes.first;
  }
}

class RecordingAnalytics implements Analytics {
  final List<String> events = [];
  final List<Map<String, Object>> parameters = [];

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async {
    events.add(name);
    this.parameters.add(parameters);
  }
}

CertificateDetails details({
  String hex = 'ab',
  DateTime? notBefore,
  DateTime? notAfter,
}) => CertificateDetails(
  fingerprint: CertificateFingerprint.parse(hex.padRight(64, 'c')),
  subject: 'CN=nas.example',
  issuer: 'CN=nas.example',
  notBefore: notBefore ?? DateTime.utc(2025),
  notAfter: notAfter ?? DateTime.utc(2030),
);

PinKey pinKeyFor(String id) =>
    PinKey(profileId: id, host: 'sonarr.example', port: 443);

/// Everything a servers screen test needs, wired as provider overrides.
class UiHarness {
  UiHarness({
    List<ServerEntry> servers = const [],
    FakeTester? tester,
    this.health = const {},
    this.neverLoads = false,
    this.listError = false,
  }) : repo = FakeServerRepository(servers),
       tester = tester ?? FakeTester();

  final FakeServerRepository repo;
  final FakeTester tester;
  final InMemoryPinStore pins = InMemoryPinStore();
  final RecordingSecureScreen secureScreen = RecordingSecureScreen();
  final RecordingAnalytics analytics = RecordingAnalytics();

  /// Health by server id; missing ids stay "checking" forever.
  final Map<String, ServerHealth> health;
  final bool neverLoads;
  final bool listError;

  List<Override> get overrides => [
    serverRepositoryProvider.overrideWithValue(repo),
    connectionTesterProvider.overrideWithValue(tester),
    healthTesterProvider.overrideWithValue(tester),
    pinStoreProvider.overrideWithValue(pins),
    secureScreenProvider.overrideWithValue(secureScreen),
    analyticsProvider.overrideWithValue(analytics),
    if (neverLoads)
      serversProvider.overrideWith(
        (ref) => StreamController<List<ServerEntry>>().stream,
      ),
    if (listError)
      serversProvider.overrideWith(
        (ref) => Stream<List<ServerEntry>>.error(StateError('read failed')),
      ),
    serverHealthProvider.overrideWith((ref, id) {
      final h = health[id];
      if (h == null) return Completer<ServerHealth>().future;
      return Future.value(h);
    }),
  ];

  ///
  /// Skeletons shimmer forever unless motion is reduced, which would keep
  /// `pumpAndSettle` from finishing; tests run with reduced motion. Failed
  /// providers are not retried (retry timers would also keep frames coming).
  Widget app(HarnessVariant variant, Widget home) => ProviderScope(
    retry: (_, _) => null,
    overrides: overrides,
    child: harnessApp(
      variant,
      ConsolarrEffectsScope(reduceMotion: true, child: home),
    ),
  );
}
