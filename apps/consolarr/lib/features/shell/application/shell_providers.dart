// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The server list for UI that is visible on the first frame. Stays in the
/// loading state until the first frame is done, so reading it never starts
/// database work before then.
final uiServersProvider = Provider<AsyncValue<List<ServerEntry>>>((ref) {
  if (!ref.watch(firstFrameDoneProvider)) return const AsyncValue.loading();
  return ref.watch(serversProvider);
});
