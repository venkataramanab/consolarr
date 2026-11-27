// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ids of the active server of every service kind that has one. Follows
/// `ServerRepository.setActive` and saves through
/// `activeConnectionKeyProvider`; no manual invalidation.
final activeServerIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final servers = await ref.watch(serversProvider.future);
  final ids = <String>{};
  for (final kind in {for (final s in servers) s.profile.kind}) {
    final key = await ref.watch(activeConnectionKeyProvider(kind).future);
    final id = key.serverId;
    if (id != null) ids.add(id);
  }
  return ids;
});
