// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';

/// The download queue. Live data: nothing is cached, because a stale queue
/// would be misleading; an unreachable server shows the last list in memory
/// (kept by the notifier) under a banner.
class SonarrQueueRepository {
  SonarrQueueRepository({required SonarrApi api}) : _api = api;

  final SonarrApi _api;

  Future<Result<List<ArrQueueItem>>> load() => _api.queue();

  Future<Result<void>> remove(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  }) => _api.removeQueueItem(
    id,
    removeFromClient: removeFromClient,
    blocklist: blocklist,
  );
}
