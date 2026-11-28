// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/src/events/catalog.dart';
import 'package:observability/src/redactor.dart';

/// What a crash sink may receive: **never the error object or its message**.
///
/// An exception message can carry a host, a key, a title or a path, so the
/// consent gate reduces every error to this typed payload before anything
/// leaves it:
///
///  * the runtime type name, restricted to identifier characters;
///  * an [ErrorCategoryParam] (a closed enum) when the app can classify the
///    error;
///  * scrubbed frames: only `package:<name>/<file>.dart:<line>` or
///    `<file>.dart:<line>`. Directories of a `file:` frame (they contain user
///    and build paths), columns, function names and arguments are dropped, and
///    every kept frame also passes the [Redactor].
///
/// It is the `error` the sink gets, and [stackTrace] is the `StackTrace` it
/// gets: sinks need no special handling and cannot reach the original.
final class CrashPayload implements Exception {
  const CrashPayload({
    required this.typeName,
    this.category,
    this.frames = const [],
  });

  /// Reduces [error] and [stackTrace]. [categorize] lets the app map its own
  /// typed errors to a category (observability does not know them).
  factory CrashPayload.from(
    Object error,
    StackTrace? stackTrace, {
    ErrorCategoryParam? Function(Object error)? categorize,
  }) {
    ErrorCategoryParam? category;
    try {
      category = categorize?.call(error);
    } on Object {
      category = null;
    }
    return CrashPayload(
      typeName: _typeName(error),
      category: category,
      frames: _frames(stackTrace),
    );
  }

  /// Longest type name and number of frames kept.
  static const maxTypeNameLength = 64;
  static const maxFrames = 30;

  final String typeName;
  final ErrorCategoryParam? category;

  /// For example `package:consolarr/src/x.dart:12`.
  final List<String> frames;

  /// The scrubbed frames as a trace the sink can attach.
  StackTrace get stackTrace => StackTrace.fromString(
    [for (var i = 0; i < frames.length; i++) '#$i      ${frames[i]}']
        .join('\n'),
  );

  static final _identifier = RegExp(r'[^A-Za-z0-9_$<>]');

  static String _typeName(Object error) {
    final name = error.runtimeType.toString().replaceAll(_identifier, '');
    if (name.isEmpty) return 'Object';
    return name.length > maxTypeNameLength
        ? name.substring(0, maxTypeNameLength)
        : name;
  }

  static final _package = RegExp(
    r'package:([A-Za-z0-9_]+)/([A-Za-z0-9_/]+\.dart)(?:[: ](\d+))?',
  );
  static final _file = RegExp(
    r'(?:file|dart|org-dartlang-[a-z]+):[^\s)]*?([A-Za-z0-9_]+\.dart)(?:[: ](\d+))?',
  );

  /// The only package names a frame may keep: this workspace's own packages,
  /// Flutter and the Dart SDK. A trace is attacker-influenced text (a forged
  /// `StackTrace` string), so any other package or file name is replaced.
  static const allowedPackages = {
    'consolarr',
    'consolarr_play',
    'core',
    'security',
    'arr_api',
    'torrent_clients',
    'design_system',
    'observability',
    'l10n',
    'test_harness',
    'flutter',
    'flutter_test',
    'dart',
  };

  static const _other = '<other>';
  static final _fileShape = RegExp(r'^[a-z0-9_]+(/[a-z0-9_]+)*\.dart$');

  static List<String> _frames(StackTrace? trace) {
    if (trace == null) return const [];
    final out = <String>[];
    for (final line in trace.toString().split('\n')) {
      if (out.length >= maxFrames) break;
      String? frame;
      final p = _package.firstMatch(line);
      if (p != null) {
        final line = p[3] == null ? '' : ':${p[3]}';
        // Dart file names are lower snake case; anything else in an allowed
        // package is not one of our files.
        final ours =
            allowedPackages.contains(p[1]) && _fileShape.hasMatch(p[2]!);
        frame = ours
            ? 'package:${p[1]}/${p[2]}$line'
            : 'package:${allowedPackages.contains(p[1]) ? p[1] : _other}/'
                  '$_other$line';
      } else {
        final f = _file.firstMatch(line);
        if (f != null) {
          final isSdk = line.contains(RegExp(r'(?:^|[\s(])dart:'));
          final at = f[2] == null ? '' : ':${f[2]}';
          frame = isSdk ? '${f[1]}$at' : '$_other$at';
        }
      }
      if (frame == null) continue;
      // Defence in depth: the frame is already a closed shape.
      out.add(const Redactor().redactText(frame));
    }
    return out;
  }

  @override
  String toString() =>
      'CrashPayload(type=$typeName, category=${category?.code})';
}
