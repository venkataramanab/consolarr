// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ids of the active server of every service kind that has one. Invalidate
/// after `ServerRepository.setActive`.
final activeServerIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final servers = await ref.watch(serversProvider.future);
  final repo = ref.watch(serverRepositoryProvider);
  final ids = <String>{};
  for (final kind in {for (final s in servers) s.profile.kind}) {
    final id = await repo.activeId(kind);
    if (id != null) ids.add(id);
  }
  return ids;
});
