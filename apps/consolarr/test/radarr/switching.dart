// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/data/radarr_repository.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The active Radarr context, replaceable by a test to simulate a server
/// switch.
class ContextHolder extends Notifier<RadarrContext?> {
  ContextHolder(this._initial);
  final RadarrContext? _initial;

  @override
  RadarrContext? build() => _initial;

  void activate(RadarrContext? next) => state = next;
}

typedef ContextHolderProvider = NotifierProvider<ContextHolder, RadarrContext?>;

/// A context for [api] with its own server id.
RadarrContext serverContext(FakeRadarrApi api, String id) => RadarrContext(
  api: api,
  repository: RadarrRepository(
    api: api,
    cache: MemoryPayloadCache(),
    serverId: id,
    clock: () => fixedNow,
  ),
  serverId: id,
  dio: Dio(),
);

/// A container whose active server can be switched with
/// `c.read(holder.notifier).activate(...)`.
(ProviderContainer, ContextHolderProvider) switchingContainer(
  RadarrContext first, {
  Duration pollInterval = Duration.zero,
  List<Override> extra = const [],
  MemoryPrefs? prefs,
}) {
  final holder = ContextHolderProvider(() => ContextHolder(first));
  final c = ProviderContainer(
    overrides: [
      radarrContextProvider.overrideWith((ref) async => ref.watch(holder)),
      radarrPrefsProvider.overrideWithValue(prefs ?? MemoryPrefs()),
      clockProvider.overrideWithValue(() => fixedNow),
      appLockedProvider.overrideWithValue(false),
      commandPollIntervalProvider.overrideWithValue(pollInterval),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return (c, holder);
}

/// Lets queued microtasks and zero-delay timers run.
Future<void> settle([int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A fake API whose slow calls wait for the test and that counts calls.
class GatedApi extends FakeRadarrApi {
  GatedApi({super.moviesResult});

  Completer<void>? moviesGate;
  Completer<void>? updateGate;
  Completer<void>? removeGate;
  Completer<void>? grabGate;
  Completer<void>? commandGate;
  int queueCalls = 0;
  int movieCalls = 0;
  int grabCalls = 0;
  int addCalls = 0;

  @override
  Future<Result<List<RadarrMovie>>> movies() async {
    final r = await super.movies();
    await moviesGate?.future;
    return r;
  }

  @override
  Future<Result<RadarrMovie>> movie(int id) {
    movieCalls++;
    return super.movie(id);
  }

  @override
  Future<Result<RadarrMovie>> updateMovie(
    int id, {
    bool? monitored,
    int? qualityProfileId,
    MinimumAvailability? minimumAvailability,
    List<int>? tags,
  }) async {
    await updateGate?.future;
    return super.updateMovie(
      id,
      monitored: monitored,
      qualityProfileId: qualityProfileId,
      minimumAvailability: minimumAvailability,
      tags: tags,
    );
  }

  @override
  Future<Result<List<ArrQueueItem>>> queue() async {
    queueCalls++;
    return super.queue();
  }

  @override
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  }) async {
    await removeGate?.future;
    return super.removeQueueItem(
      id,
      removeFromClient: removeFromClient,
      blocklist: blocklist,
    );
  }

  @override
  Future<Result<void>> grab(ArrRelease release) async {
    grabCalls++;
    await grabGate?.future;
    return super.grab(release);
  }

  @override
  Future<Result<ArrCommand>> command(int id) async {
    await commandGate?.future;
    return super.command(id);
  }

  @override
  Future<Result<RadarrMovie>> addMovie(AddMovieRequest request) {
    addCalls++;
    return super.addMovie(request);
  }
}
