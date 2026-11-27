// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:observability/src/logger.dart';
import 'package:observability/src/redactor.dart';

/// One captured log line. The message is already redacted.
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final LogLevel level;
  final String message;
}

/// The opt-in in-app log (SET-04): off by default, memory only, a ring
/// buffer with a cap, cleared on request, when turned off and when the
/// process ends. Messages are redacted at write time; the bundle redacts them
/// again.
class DiagnosticsLog {
  DiagnosticsLog({
    this.capacity = 500,
    this.redactor = const Redactor(),
    DateTime Function()? clock,
  }) : assert(capacity > 0, 'capacity > 0'),
       _clock = clock ?? DateTime.now;

  final int capacity;
  final Redactor redactor;
  final DateTime Function() _clock;

  final List<LogEntry> _entries = [];
  final List<void Function()> _listeners = [];
  bool _enabled = false;
  LogLevel _level = LogLevel.info;

  bool get enabled => _enabled;

  /// Turning the log off also drops what it holds.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _entries.clear();
    _notify();
  }

  LogLevel get level => _level;
  set level(LogLevel value) {
    if (_level == value) return;
    _level = value;
    _notify();
  }

  /// Oldest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Records [message] (redacted) when the log is on and [level] passes the
  /// selected level. Never throws.
  void add(LogLevel level, String message) {
    if (!_enabled || level.index < _level.index) return;
    _entries.add(
      LogEntry(
        time: _clock().toUtc(),
        level: level,
        message: redactor.redactText(message),
      ),
    );
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    _notify();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    _notify();
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

/// A stricter second pass for text that leaves the device: on top of
/// [Redactor] it removes URLs, magnet links, e-mail addresses, IP addresses,
/// host names, file paths, quoted strings (titles), values of keys that name
/// a person or a media item, and any caller-supplied [knownValues] (server
/// names, hosts, user names). It over-redacts on purpose.
///
/// A title that appears bare, without quotes or a key, cannot be recognised;
/// the logging policy is that titles are never logged, and the scrubber is the
/// second line of defence.
class DiagnosticsScrubber {
  const DiagnosticsScrubber({
    this.knownValues = const [],
    this.redactor = const Redactor(),
  });

  /// Literal values to remove wherever they occur (case-insensitive).
  final List<String> knownValues;
  final Redactor redactor;

  static const _mark = Redactor.placeholder;

  static final _magnet = RegExp(r'magnet:\?\S+', caseSensitive: false);
  static final _url = RegExp(r'\b[a-zA-Z][a-zA-Z0-9+.\-]*://\S+');
  static final _winPathExt = RegExp(
    r'[A-Za-z]:\\[^\r\n"]*?\.[A-Za-z0-9]{2,5}\b',
  );
  static final _winPath = RegExp(r'[A-Za-z]:\\\S+');
  static final _unixPathExt = RegExp(
    r'(?<![\w:/.])/(?:[^/\r\n"]+/)+[^/\r\n"]*?\.[A-Za-z0-9]{2,5}\b',
  );
  static final _unixPath = RegExp(r'(?<![\w:/.])(?:/[^\s/"<>|]+){2,}');
  static final _email = RegExp(r'[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+');
  static final _keyed = RegExp(
    r'\b(title|name|user|username|login|host|hostname|path|file|filename|'
    r'series|movie|show|torrent|hash|server|address)\b([ \t]*[=:][ \t]*)'
    r'([^\r\n,;&]*)',
    caseSensitive: false,
  );
  static final _doubleQuoted = RegExp(r'"[^"\r\n]{1,200}"');
  static final _singleQuoted = RegExp(r"(?<![\w])'[^'\r\n]{1,200}'(?!\w)");
  static final _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
  static final _ipv6 = RegExp(
    r'\b[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{0,4}){2,7}\b',
  );
  static final _timeLike = RegExp(r'^\d{1,2}(?::\d{1,2}){1,2}$');
  static final _host = RegExp(
    r'\b[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?(?:\.[a-z0-9\-]+)*\.[a-z]{2,}\b',
    caseSensitive: false,
  );

  /// `nas:8989`: a single-label host with a port (no dot, so [_host] misses it).
  static final _labelPort = RegExp(
    r'(?<![\w\-.:/])[A-Za-z][A-Za-z0-9\-]*:\d{2,5}\b(?!:)',
  );

  /// Passkeys and similar: bare hex or base32 runs of 16 or more characters.
  static final _hexRun = RegExp(
    r'(?<![0-9A-Za-z])[0-9a-fA-F]{16,}(?![0-9A-Za-z])',
  );
  static final _base32Upper = RegExp(
    r'(?<![0-9A-Za-z])[A-Z2-7]{16,}(?![0-9A-Za-z])',
  );
  static final _base32Lower = RegExp(
    r'(?<![0-9A-Za-z])(?=[a-z2-7]*[2-7])[a-z2-7]{16,}(?![0-9A-Za-z])',
  );

  /// Returns [line] with everything above removed. Idempotent.
  String scrub(String line) {
    var out = line;
    for (final v in knownValues) {
      if (v.length < 3) continue;
      out = out.replaceAll(
        RegExp(RegExp.escape(v), caseSensitive: false),
        _mark,
      );
    }
    out = out.replaceAll(_magnet, _mark);
    out = redactor.redactText(out);
    out = out.replaceAll(_url, _mark);
    out = out.replaceAll(_winPathExt, _mark).replaceAll(_winPath, _mark);
    out = out.replaceAll(_unixPathExt, _mark).replaceAll(_unixPath, _mark);
    out = out.replaceAll(_email, _mark);
    out = out.replaceAllMapped(_keyed, (m) => '${m[1]}${m[2]}$_mark');
    out = out.replaceAll(_doubleQuoted, '"$_mark"');
    out = out.replaceAllMapped(_singleQuoted, (_) => "'$_mark'");
    out = out.replaceAll(_ipv4, _mark);
    out = out.replaceAllMapped(
      _ipv6,
      (m) => _timeLike.hasMatch(m[0]!) ? m[0]! : _mark,
    );
    out = out.replaceAll(_host, _mark);
    out = out.replaceAll(_labelPort, _mark);
    out = out.replaceAll(_hexRun, _mark);
    out = out.replaceAll(_base32Upper, _mark);
    out = out.replaceAll(_base32Lower, _mark);
    return out;
  }
}

/// Facts about the install that go in the bundle. No identity.
class DiagnosticsInfo {
  const DiagnosticsInfo({
    required this.appVersion,
    required this.buildMode,
    required this.platform,
    required this.locale,
  });

  final String appVersion;

  /// `debug`, `profile` or `release`.
  final String buildMode;

  /// For example `Android API 34`.
  final String platform;

  /// App locale tag, for example `en`.
  final String locale;
}

/// One titled block of the bundle; the preview shows every section.
class DiagnosticsSection {
  const DiagnosticsSection({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;
}

/// The redacted diagnostics bundle (SET-04). [text] is what the preview shows,
/// what the shared file contains byte for byte ([bytes]) and what the GitHub
/// issue body is built from. Nothing outside the sections is included.
class DiagnosticsBundle {
  const DiagnosticsBundle._(this.sections, this.text);

  /// Section titles are English: the bundle is read by maintainers.
  factory DiagnosticsBundle.build({
    required DiagnosticsInfo info,
    required List<String> errorCategories,
    required List<LogEntry> entries,
    DiagnosticsScrubber scrubber = const DiagnosticsScrubber(),
  }) {
    String s(String v) => scrubber.scrub(v);
    final sections = [
      DiagnosticsSection(
        id: 'app',
        title: 'App',
        body: 'version: ${s(info.appVersion)}\nbuild: ${s(info.buildMode)}',
      ),
      DiagnosticsSection(
        id: 'platform',
        title: 'Platform',
        body: s(info.platform),
      ),
      DiagnosticsSection(id: 'locale', title: 'Locale', body: s(info.locale)),
      DiagnosticsSection(
        id: 'error_categories',
        title: 'Error categories',
        body: errorCategories.isEmpty
            ? '(none)'
            : errorCategories.map(s).join('\n'),
      ),
      DiagnosticsSection(
        id: 'log',
        title: 'Log',
        body: entries.isEmpty
            ? '(empty)'
            : entries
                  .map(
                    (e) =>
                        '${e.time.toIso8601String()} '
                        '${e.level.name.toUpperCase()} ${s(e.message)}',
                  )
                  .join('\n'),
      ),
    ];
    final text = [
      'Consolarr diagnostics',
      for (final section in sections) '## ${section.title}\n${section.body}',
    ].join('\n\n');
    return DiagnosticsBundle._(List.unmodifiable(sections), text);
  }

  final List<DiagnosticsSection> sections;
  final String text;

  /// UTF-8 bytes of [text]: exactly what the share sheet receives.
  List<int> get bytes => utf8.encode(text);
}

/// Builds the pre-filled GitHub "new issue" address. The app never contacts
/// GitHub: the address is opened in the browser on an explicit tap.
abstract final class GithubIssueLink {
  /// Browsers and GitHub accept long addresses, but proxies do not; stay well
  /// below the common 8 KB limit.
  static const maxUrlLength = 6000;

  static Uri build({
    required Uri repository,
    required String title,
    required String body,
    String truncationNote = '[truncated: attach the shared file]',
  }) {
    if (repository.scheme != 'https' || repository.host.isEmpty) {
      throw ArgumentError.value(repository, 'repository', 'must be https');
    }
    final base = repository.path.endsWith('/')
        ? repository.path.substring(0, repository.path.length - 1)
        : repository.path;
    Uri uri(String b) => Uri(
      scheme: 'https',
      host: repository.host,
      path: '$base/issues/new',
      queryParameters: {'title': title, 'body': b},
    );

    if (uri(body).toString().length <= maxUrlLength) return uri(body);
    var low = 0;
    var high = body.length;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (uri(_cut(body, mid, truncationNote)).toString().length <=
          maxUrlLength) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return uri(_cut(body, low, truncationNote));
  }

  static String _cut(String body, int n, String note) {
    var end = n;
    if (end > 0 && end < body.length) {
      final unit = body.codeUnitAt(end - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    }
    return '${body.substring(0, end)}\n\n$note';
  }
}
