// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:developer' as developer;

import 'package:observability/src/diagnostics.dart';
import 'package:observability/src/redactor.dart';

enum LogLevel {
  debug(500),
  info(800),
  warning(900),
  error(1000);

  const LogLevel(this.value);

  /// `dart:developer` numeric level.
  final int value;
}

/// Receives already-redacted log lines.
typedef LogSink = void Function(LogLevel level, String message);

/// The single place allowed to write logs (the `consolarr_no_print` lint
/// exempts this file). Every message and error is redacted first.
class AppLogger {
  AppLogger({
    LogSink? sink,
    this.redactor = const Redactor(),
    this.scrubber = const DiagnosticsScrubber(),
    this.minLevel = LogLevel.info,
    this.diagnostics,
  }) : _sink = sink ?? _defaultSink;

  final Redactor redactor;

  /// Applied after [redactor]: no address, host, path or quoted title
  /// reaches a sink.
  final DiagnosticsScrubber scrubber;
  final LogLevel minLevel;
  final LogSink _sink;

  /// The opt-in in-app log (SET-04); it applies its own level.
  final DiagnosticsLog? diagnostics;

  static void _defaultSink(LogLevel level, String message) {
    developer.log(message, name: 'consolarr', level: level.value);
  }

  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warning(String message, {Object? error}) =>
      _log(LogLevel.warning, message, error: error);
  void error(String message, {Object? error}) =>
      _log(LogLevel.error, message, error: error);

  void _log(LogLevel level, String message, {Object? error}) {
    final captured = diagnostics?.enabled ?? false;
    if (level.index < minLevel.index && !captured) return;
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(': $error');
    final text = scrubber.scrub(redactor.redactText(buffer.toString()));
    // One scrub, whichever sinks the line reaches.
    diagnostics?.addScrubbed(level, text);
    if (level.index >= minLevel.index) _sink(level, text);
  }
}
