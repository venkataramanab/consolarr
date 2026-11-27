// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:consolarr/features/servers/data/server_secret_keys.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart';
import 'package:security/security.dart';

/// [ServerRepository] on drift (profiles) and `SecretStore` (secrets).
///
/// Credential fields of a [ServerDraft]: `null` keeps the stored secret, an
/// empty string deletes it, any other value replaces it.
class DriftServerRepository implements ServerRepository {
  DriftServerRepository({
    required AppDatabase db,
    required SecretStore secrets,
    required PayloadCache cache,
    this.onServerAdded,
    Random? random,
  }) : _db = db,
       _secrets = secrets,
       _cache = cache,
       _random = random ?? Random.secure();

  final AppDatabase _db;
  final SecretStore _secrets;
  final PayloadCache _cache;
  final Random _random;

  /// Called once for each newly created server (not for edits).
  final void Function(ServerProfile profile)? onServerAdded;

  static String _activeKey(ServiceKind kind) => 'active/${kind.name}';

  String _newId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  // --- reads ----------------------------------------------------------------

  @override
  Stream<List<ServerEntry>> watchAll() {
    final query = _db.select(_db.serverRows)
      ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]);
    return query.watch().asyncMap(_entries);
  }

  Future<List<ServerEntry>> _entries(List<ServerRow> rows) async {
    final out = <ServerEntry>[];
    for (final row in rows) {
      final entry = await _toEntry(row);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  @override
  Future<ServerEntry?> find(String id) async {
    final row = await (_db.select(
      _db.serverRows,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  /// Rows that no longer parse (hand-edited, future schema) are skipped, not
  /// fatal.
  Future<ServerEntry?> _toEntry(ServerRow row) async {
    final kind = ServiceKind.values.asNameMap()[row.kind];
    final mode = AuthMode.values.asNameMap()[row.authMode];
    if (kind == null || mode == null) return null;
    final profile = ServerProfile.parse(
      id: row.id,
      name: row.name,
      kind: kind,
      address: row.address,
      pathPrefix: row.pathPrefix,
      authMode: mode,
      allowCleartext: row.allowCleartext,
      headerNames: _splitNames(row.headerNames),
      alternateAddress: row.alternateAddress,
    ).valueOrNull;
    if (profile == null) return null;
    return ServerEntry(
      profile: profile,
      sortOrder: row.sortOrder,
      isStartup: row.isStartup,
      needsCredentials: await _needsCredentials(profile),
    );
  }

  static List<String> _splitNames(String s) =>
      s.isEmpty ? const [] : s.split('\n');

  /// Credential path: an unreadable store reads as "no secret", which the UI
  /// answers with a re-entry prompt. (The pin path must NOT do this.)
  Future<String?> _read(String key) async {
    try {
      return await _secrets.read(key);
    } on SecretStoreUnavailable {
      return null;
    }
  }

  Future<bool> _needsCredentials(ServerProfile p) async {
    Future<bool> missing(String key) async =>
        (await _read(key))?.isNotEmpty != true;
    switch (p.authMode) {
      case AuthMode.none:
        break;
      case AuthMode.apiKey:
        if (await missing(ServerSecretKeys.apiKey(p.id))) return true;
      case AuthMode.basic:
        if (await missing(ServerSecretKeys.username(p.id)) ||
            await missing(ServerSecretKeys.password(p.id))) {
          return true;
        }
    }
    for (final name in p.headerNames) {
      if (await missing(ServerSecretKeys.header(p.id, name))) return true;
    }
    return false;
  }

  @override
  Future<ServerCredentials> loadCredentials(ServerProfile profile) async {
    final id = profile.id;
    final headers = <HeaderEntry>[];
    for (final name in profile.headerNames) {
      final v = await _read(ServerSecretKeys.header(id, name));
      if (v != null) headers.add(HeaderEntry(name: name, value: v));
    }
    return ServerCredentials(
      apiKey: await _read(ServerSecretKeys.apiKey(id)),
      username: await _read(ServerSecretKeys.username(id)),
      password: await _read(ServerSecretKeys.password(id)),
      headers: headers,
    );
  }

  // --- writes ---------------------------------------------------------------

  @override
  Future<Result<ServerEntry>> save(ServerDraft draft) async {
    final id = draft.id ?? _newId();
    // The editor may pre-assign an id for a new server (so a certificate pin
    // made during the connection test belongs to the saved server); an id that
    // is not stored yet is still a new server.
    final isNew = draft.id == null || await find(id) == null;
    final headers = draft.credentials.headers;
    final existing = isNew ? null : await find(id);
    final parsed = ServerProfile.parse(
      id: id,
      name: draft.name.trim(),
      kind: draft.kind,
      address: draft.address,
      pathPrefix: draft.pathPrefix,
      authMode: draft.authMode,
      allowCleartext: draft.allowCleartext,
      headerNames: [for (final h in headers) h.name],
      // The editor has no field for it yet: keep what is stored.
      alternateAddress: existing?.profile.alternateAddress?.toString(),
    );
    final profile = parsed.valueOrNull;
    if (profile == null) return Result.err(parsed.errorOrNull!);

    final previous = existing?.profile;
    if (previous != null && _identityChanged(previous, profile)) {
      await _forgetIdentity(previous);
      if (_originChanged(previous, profile)) {
        await _deleteSecrets(id, previous.headerNames);
      }
    }
    final sortOrder = existing?.sortOrder ?? await _nextSortOrder();

    await _db
        .into(_db.serverRows)
        .insertOnConflictUpdate(
          ServerRowsCompanion.insert(
            id: id,
            name: profile.name,
            kind: profile.kind.name,
            address: profile.address.toString(),
            alternateAddress: Value(profile.alternateAddress?.toString()),
            pathPrefix: Value(profile.pathPrefix),
            authMode: profile.authMode.name,
            headerNames: Value(profile.headerNames.join('\n')),
            allowCleartext: Value(profile.allowCleartext),
            sortOrder: Value(sortOrder),
            isStartup: Value(existing?.isStartup ?? false),
          ),
        );

    await _writeSecrets(profile, draft.credentials, existing?.profile);
    await _bumpRevision(id);
    if (isNew) onServerAdded?.call(profile);
    return Result.ok((await find(id))!);
  }

  static bool _identityChanged(ServerProfile a, ServerProfile b) =>
      a.kind != b.kind ||
      a.address != b.address ||
      a.pathPrefix != b.pathPrefix;

  static bool _originChanged(ServerProfile a, ServerProfile b) =>
      a.address.scheme != b.address.scheme ||
      a.address.host.toLowerCase() != b.address.host.toLowerCase() ||
      a.address.port != b.address.port;

  /// Cached payloads and certificate pins belong to the old identity.
  Future<void> _forgetIdentity(ServerProfile old) async {
    await _cache.deleteForServer(old.id);
    await _deletePins(old.id, [old.address, old.alternateAddress]);
  }

  Future<void> _deletePins(String id, List<Uri?> addresses) async {
    for (final uri in addresses) {
      if (uri == null) continue;
      try {
        await _secrets.delete(
          PinKey(profileId: id, host: uri.host, port: uri.port).storageKey,
        );
      } on ArgumentError {
        // An address that cannot form a pin key has no pin to remove.
      }
    }
  }

  Future<void> _deleteSecrets(String id, List<String> headerNames) async {
    await _secrets.delete(ServerSecretKeys.apiKey(id));
    await _secrets.delete(ServerSecretKeys.username(id));
    await _secrets.delete(ServerSecretKeys.password(id));
    for (final name in headerNames) {
      await _secrets.delete(ServerSecretKeys.header(id, name));
    }
  }

  static String _revisionKey(String id) => 'rev/$id';

  Future<int> _revision(String id) async {
    final row = await (_db.select(
      _db.appStateRows,
    )..where((r) => r.key.equals(_revisionKey(id)))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _bumpRevision(String id) async => _db
      .into(_db.appStateRows)
      .insertOnConflictUpdate(
        AppStateRowsCompanion.insert(
          key: _revisionKey(id),
          value: '${await _revision(id) + 1}',
        ),
      );

  Future<int> _nextSortOrder() async {
    final max = _db.serverRows.sortOrder.max();
    final row = await (_db.selectOnly(
      _db.serverRows,
    )..addColumns([max])).getSingle();
    final current = row.read(max);
    return current == null ? 0 : current + 1;
  }

  Future<void> _put(String key, String? value) async {
    if (value == null) return;
    if (value.isEmpty) {
      await _secrets.delete(key);
    } else {
      await _secrets.write(key, value);
    }
  }

  Future<void> _writeSecrets(
    ServerProfile p,
    ServerCredentials c,
    ServerProfile? previous,
  ) async {
    final id = p.id;
    // Secrets of an auth mode that is no longer used must not linger.
    if (p.authMode != AuthMode.apiKey) {
      await _secrets.delete(ServerSecretKeys.apiKey(id));
    } else {
      await _put(ServerSecretKeys.apiKey(id), c.apiKey);
    }
    if (p.authMode != AuthMode.basic) {
      await _secrets.delete(ServerSecretKeys.username(id));
      await _secrets.delete(ServerSecretKeys.password(id));
    } else {
      await _put(ServerSecretKeys.username(id), c.username);
      await _put(ServerSecretKeys.password(id), c.password);
    }
    for (final h in c.headers) {
      await _put(ServerSecretKeys.header(id, h.name), h.value);
    }
    final keep = p.headerNames.map((n) => n.toLowerCase()).toSet();
    for (final old in previous?.headerNames ?? const <String>[]) {
      if (!keep.contains(old.toLowerCase())) {
        await _secrets.delete(ServerSecretKeys.header(id, old));
      }
    }
  }

  @override
  Future<void> delete(String id) async {
    // Work from the raw row, not the parsed profile: a row that no longer
    // parses (hand-edited, future schema) must still be removable together
    // with its secrets.
    final row = await (_db.select(
      _db.serverRows,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row != null) {
      await _deleteSecrets(id, _splitNames(row.headerNames));
      // Removing a pin is not creating one; no confirmation is involved.
      await _deletePins(id, [
        Uri.tryParse(row.address),
        if (row.alternateAddress != null) Uri.tryParse(row.alternateAddress!),
      ]);
    }
    await _cache.deleteForServer(id);
    await (_db.delete(_db.serverRows)..where((r) => r.id.equals(id))).go();
    await (_db.delete(
      _db.appStateRows,
    )..where((r) => r.key.equals(_revisionKey(id)))).go();
    for (final kind in ServiceKind.values) {
      final key = _activeKey(kind);
      await (_db.delete(
        _db.appStateRows,
      )..where((r) => r.key.equals(key) & r.value.equals(id))).go();
    }
  }

  @override
  Future<void> reorder(List<String> idsInOrder) async {
    await _db.transaction(() async {
      final rows = await (_db.select(
        _db.serverRows,
      )..orderBy([(r) => OrderingTerm.asc(r.sortOrder)])).get();
      final byId = {for (final r in rows) r.id: r};
      final ordered = <String>[...idsInOrder.where(byId.containsKey).toSet()];
      ordered.addAll(rows.map((r) => r.id).where((i) => !ordered.contains(i)));
      for (var i = 0; i < ordered.length; i++) {
        await (_db.update(_db.serverRows)
              ..where((r) => r.id.equals(ordered[i])))
            .write(ServerRowsCompanion(sortOrder: Value(i)));
      }
    });
  }

  @override
  Future<void> setStartup(String? id) async {
    await _db.transaction(() async {
      await _db
          .update(_db.serverRows)
          .write(const ServerRowsCompanion(isStartup: Value(false)));
      if (id != null) {
        await (_db.update(_db.serverRows)..where((r) => r.id.equals(id))).write(
          const ServerRowsCompanion(isStartup: Value(true)),
        );
      }
    });
  }

  @override
  Future<void> setActive(ServiceKind kind, String id) => _db
      .into(_db.appStateRows)
      .insertOnConflictUpdate(
        AppStateRowsCompanion.insert(key: _activeKey(kind), value: id),
      );

  @override
  Stream<ConnectionKey> watchConnectionKey(ServiceKind kind) {
    Future<ConnectionKey> current() async {
      final id = await activeId(kind);
      return ConnectionKey(id, id == null ? 0 : await _revision(id));
    }

    return _db
        .customSelect('SELECT 1', readsFrom: {_db.serverRows, _db.appStateRows})
        .watch()
        .asyncMap((_) => current())
        .distinct();
  }

  @override
  Future<String?> activeId(ServiceKind kind) async {
    final state = await (_db.select(
      _db.appStateRows,
    )..where((r) => r.key.equals(_activeKey(kind)))).getSingleOrNull();
    final rows =
        await (_db.select(_db.serverRows)
              ..where((r) => r.kind.equals(kind.name))
              ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
            .get();
    if (state != null && rows.any((r) => r.id == state.value)) {
      return state.value;
    }
    return rows.isEmpty ? null : rows.first.id;
  }
}
