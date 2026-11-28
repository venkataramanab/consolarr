// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:consolarr/features/torrents/application/torrent_link.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/data/system_file_picker.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// The most files one pick may add. The platform picker copies every chosen
/// file into the app cache before Dart sees any of them, so the rest of a
/// larger pick is discarded unread and reported.
const maxPickedTorrentFiles = 20;

/// A `.torrent` file chosen in the system picker. The size is checked before
/// the bytes are read from the picker's copy; the name is for the screen,
/// never for logs.
class PickedTorrentFile {
  const PickedTorrentFile({
    required this.name,
    required this.length,
    required this.readBytes,
    this.discard,
  });

  final String name;
  final Future<int> Function() length;
  final Future<Uint8List> Function() readBytes;

  /// Deletes the picker's cached copy (it may hold a tracker passkey). Called
  /// once the file was read or skipped, whatever the outcome.
  final Future<void> Function()? discard;
}

/// Opens the system picker (no storage permission) and returns the choice.
typedef TorrentFilePicker = Future<List<PickedTorrentFile>> Function();

/// The picker seam; tests override it.
final torrentFilePickerProvider = Provider<TorrentFilePicker>(
  (ref) => pickTorrentFilesFromSystem,
);

/// The result for one link or file.
class AddItemResult {
  const AddItemResult({
    this.name,
    this.error,
    this.fileProblem,
    this.labelWarning = false,
  });

  /// File name (plain text) for file results; `null` for a link.
  final String? name;
  final AppError? error;
  final FileProblem? fileProblem;

  /// The torrent was added but its label could not be applied (Deluge).
  final bool labelWarning;

  bool get ok => error == null && fileProblem == null;
}

sealed class AddState {
  const AddState();
}

final class AddIdle extends AddState {
  const AddIdle();
}

final class AddAdding extends AddState {
  const AddAdding();
}

/// Finished; [results] holds one entry per link or file.
final class AddFinished extends AddState {
  const AddFinished(this.results, {this.ignored = 0});
  final List<AddItemResult> results;

  /// Files beyond [maxPickedTorrentFiles] that were not looked at.
  final int ignored;

  int get added => results.where((r) => r.ok).length;
}

/// Adds a link or files (TOR-04, TOR-05).
///
/// Nothing is retried automatically: a dropped connection ends in a failed
/// result the user must retry by hand, so a torrent can never be added twice
/// behind their back. The link is never stored in state, a log or an event.
final addTorrentProvider =
    NotifierProvider.autoDispose<AddTorrentController, AddState>(
      AddTorrentController.new,
    );

class AddTorrentController extends Notifier<AddState> {
  @override
  AddState build() => const AddIdle();

  Future<TorrentClient?> _client() async {
    try {
      return await ref.read(torrentClientProvider.future);
    } on Object {
      return null;
    }
  }

  void _track(
    TorrentSourceParam source,
    TorrentClient client,
    bool ok, {
    bool unsupported = false,
  }) {
    final kind = ServiceKindParam.fromCode(client.kind.name);
    if (kind == null) return;
    unawaited(
      ref
          .read(eventTrackerProvider)
          .track(
            TorrentAddedEvent(
              source: source,
              client: kind,
              outcome: ok
                  ? TorrentOutcomeParam.success
                  : unsupported
                  ? TorrentOutcomeParam.unsupported
                  : TorrentOutcomeParam.failed,
            ),
          ),
    );
  }

  /// [o] with a warning listener, so a best-effort step (Deluge's label) that
  /// fails is shown next to a successful add instead of failing it.
  AddTorrentOptions _listening(
    AddTorrentOptions o,
    void Function(AddWarning) onWarning,
  ) => AddTorrentOptions(
    savePath: o.savePath,
    category: o.category,
    tags: o.tags,
    paused: o.paused,
    onWarning: onWarning,
  );

  void reset() {
    if (state is! AddAdding) state = const AddIdle();
  }

  /// Sends [link] (already validated with [parseTorrentLink]).
  Future<bool> addLink(String link, AddTorrentOptions options) async {
    if (state is AddAdding) return false;
    final parsed = parseTorrentLink(link);
    if (parsed is InvalidLink) return false;
    state = const AddAdding();
    final client = await _client();
    if (client == null) {
      if (ref.mounted) {
        state = const AddFinished([
          AddItemResult(error: AppError(ErrorCategory.networkUnreachable)),
        ]);
      }
      return false;
    }
    var labelWarning = false;
    final result = await client.addMagnetOrUrl(
      link.trim(),
      options: _listening(options, (_) => labelWarning = true),
    );
    if (!ref.mounted) return result.isOk;
    _track(
      parsed is MagnetLink ? TorrentSourceParam.magnet : TorrentSourceParam.url,
      client,
      result.isOk,
      unsupported:
          result.errorOrNull != null &&
          UnsupportedAction.isIt(result.errorOrNull!),
    );
    state = AddFinished([
      AddItemResult(error: result.errorOrNull, labelWarning: labelWarning),
    ]);
    if (result.isOk) {
      unawaited(ref.read(torrentListProvider.notifier).refresh());
    }
    return result.isOk;
  }

  Future<void> _discard(PickedTorrentFile f) async {
    try {
      await f.discard?.call();
    } on Object {
      // Best effort: the cache is also cleared by the system.
    }
  }

  /// Checks and sends each of [files] on its own, so one bad file does not
  /// stop the others. At most [maxPickedTorrentFiles] are used; the picker's
  /// cached copy of every file (used or not) is deleted as soon as it is read
  /// or skipped.
  Future<void> addFiles(
    List<PickedTorrentFile> picked,
    AddTorrentOptions options,
  ) async {
    if (picked.isEmpty) return;
    if (state is AddAdding) {
      // Another add is running: this pick is dropped, and so are its cached
      // copies (a `.torrent` can carry a tracker passkey).
      for (final f in picked) {
        await _discard(f);
      }
      return;
    }
    state = const AddAdding();
    final files = picked.take(maxPickedTorrentFiles).toList();
    for (final extra in picked.skip(maxPickedTorrentFiles)) {
      await _discard(extra);
    }
    final ignored = picked.length - files.length;
    // Whatever happens below (the controller is disposed mid-batch, an
    // exception), every copy that has not been released yet is discarded.
    final pending = [...files];
    Future<void> release(PickedTorrentFile f) async {
      pending.remove(f);
      await _discard(f);
    }

    final results = <AddItemResult>[];
    try {
      final client = await _client();
      for (final f in files) {
        if (client == null) {
          results.add(
            AddItemResult(
              name: f.name,
              error: const AppError(ErrorCategory.networkUnreachable),
            ),
          );
          await release(f);
          continue;
        }
        Uint8List bytes;
        try {
          // `length` and `readBytes` read the picker's cached copy; the platform
          // has already read the whole file once, so this cap cannot save that
          // memory: it keeps oversized data away from the network call.
          if (await f.length() > maxTorrentFileBytes) {
            results.add(
              AddItemResult(name: f.name, fileProblem: FileProblem.tooLarge),
            );
            await release(f);
            continue;
          }
          bytes = await f.readBytes();
        } on Object {
          results.add(
            AddItemResult(
              name: f.name,
              error: const AppError(ErrorCategory.parseError),
            ),
          );
          await release(f);
          continue;
        }
        await release(f);
        final problem = checkTorrentBytes(bytes);
        if (problem != null) {
          results.add(AddItemResult(name: f.name, fileProblem: problem));
          continue;
        }
        var labelWarning = false;
        final r = await client.addFile(
          bytes,
          fileName: f.name,
          options: _listening(options, (_) => labelWarning = true),
        );
        if (!ref.mounted) return;
        _track(
          TorrentSourceParam.file,
          client,
          r.isOk,
          unsupported:
              r.errorOrNull != null && UnsupportedAction.isIt(r.errorOrNull!),
        );
        results.add(
          AddItemResult(
            name: f.name,
            error: r.errorOrNull,
            labelWarning: labelWarning,
          ),
        );
      }
    } finally {
      for (final f in List.of(pending)) {
        await release(f);
      }
    }
    if (!ref.mounted) return;
    state = AddFinished(results, ignored: ignored);
    if (results.any((r) => r.ok)) {
      unawaited(ref.read(torrentListProvider.notifier).refresh());
    }
  }
}
