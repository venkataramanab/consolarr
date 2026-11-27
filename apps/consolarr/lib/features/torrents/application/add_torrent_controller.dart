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

/// A `.torrent` file chosen in the system picker. Bytes are read only after
/// the size has been checked; the name is for the screen, never for logs.
class PickedTorrentFile {
  const PickedTorrentFile({
    required this.name,
    required this.length,
    required this.readBytes,
  });

  final String name;
  final Future<int> Function() length;
  final Future<Uint8List> Function() readBytes;
}

/// Opens the system picker (no storage permission) and returns the choice.
typedef TorrentFilePicker = Future<List<PickedTorrentFile>> Function();

/// The picker seam; tests override it.
final torrentFilePickerProvider = Provider<TorrentFilePicker>(
  (ref) => pickTorrentFilesFromSystem,
);

/// The result for one link or file.
class AddItemResult {
  const AddItemResult({this.name, this.error, this.fileProblem});

  /// File name (plain text) for file results; `null` for a link.
  final String? name;
  final AppError? error;
  final FileProblem? fileProblem;

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
  const AddFinished(this.results);
  final List<AddItemResult> results;

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
    final result = await client.addMagnetOrUrl(link.trim(), options: options);
    if (!ref.mounted) return result.isOk;
    _track(
      parsed is MagnetLink ? TorrentSourceParam.magnet : TorrentSourceParam.url,
      client,
      result.isOk,
      unsupported:
          result.errorOrNull != null &&
          UnsupportedAction.isIt(result.errorOrNull!),
    );
    state = AddFinished([AddItemResult(error: result.errorOrNull)]);
    if (result.isOk) {
      unawaited(ref.read(torrentListProvider.notifier).refresh());
    }
    return result.isOk;
  }

  /// Checks and sends each of [files] on its own, so one bad file does not
  /// stop the others.
  Future<void> addFiles(
    List<PickedTorrentFile> files,
    AddTorrentOptions options,
  ) async {
    if (state is AddAdding || files.isEmpty) return;
    state = const AddAdding();
    final client = await _client();
    final results = <AddItemResult>[];
    for (final f in files) {
      if (client == null) {
        results.add(
          AddItemResult(
            name: f.name,
            error: const AppError(ErrorCategory.networkUnreachable),
          ),
        );
        continue;
      }
      Uint8List bytes;
      try {
        if (await f.length() > maxTorrentFileBytes) {
          results.add(
            AddItemResult(name: f.name, fileProblem: FileProblem.tooLarge),
          );
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
        continue;
      }
      final problem = checkTorrentBytes(bytes);
      if (problem != null) {
        results.add(AddItemResult(name: f.name, fileProblem: problem));
        continue;
      }
      final r = await client.addFile(bytes, fileName: f.name, options: options);
      if (!ref.mounted) return;
      _track(
        TorrentSourceParam.file,
        client,
        r.isOk,
        unsupported:
            r.errorOrNull != null && UnsupportedAction.isIt(r.errorOrNull!),
      );
      results.add(AddItemResult(name: f.name, error: r.errorOrNull));
    }
    if (!ref.mounted) return;
    state = AddFinished(results);
    if (results.any((r) => r.ok)) {
      unawaited(ref.read(torrentListProvider.notifier).refresh());
    }
  }
}
