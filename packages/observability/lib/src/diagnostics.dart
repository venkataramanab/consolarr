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

/// The opt-in in-app log (SET-04): off by default, memory only, a circular
/// buffer with a cap, cleared on request, when turned off and when the
/// process ends. Messages are redacted at write time and capped at
/// [maxMessageLength]; the bundle redacts them again.
///
/// Reading does not copy: [length], [entryAt] and [view] look straight into the
/// buffer, and [version] changes on every change so a listener can tell
/// whether to rebuild. [entries] is the explicit (copying) snapshot used by
/// the bundle.
class DiagnosticsLog {
  DiagnosticsLog({
    this.capacity = 500,
    this.redactor = const Redactor(),
    DateTime Function()? clock,
  }) : assert(capacity > 0, 'capacity > 0'),
       _clock = clock ?? DateTime.now;

  /// Largest stored message, marker included (about 1 KB).
  static const maxMessageLength = 1024;

  /// Appended to a message that was cut at [maxMessageLength].
  static const truncationMarker = ' ...[TRUNCATED]';

  final int capacity;
  final Redactor redactor;
  final DateTime Function() _clock;

  final List<LogEntry?> _ring = [];
  int _start = 0;
  int _version = 0;
  final List<void Function()> _listeners = [];
  bool _enabled = false;
  LogLevel _level = LogLevel.info;

  bool get enabled => _enabled;

  /// Turning the log off also drops what it holds.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _drop();
    _changed();
  }

  LogLevel get level => _level;
  set level(LogLevel value) {
    if (_level == value) return;
    _level = value;
    _changed();
  }

  /// Changes whenever the entries, the level or the on/off state change.
  int get version => _version;

  /// Number of stored entries.
  int get length => _ring.length;

  /// The entry at [index], 0 being the oldest.
  LogEntry entryAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return _ring[(_start + index) % _ring.length]!;
  }

  /// A live, read-only, oldest-first view (no copy). Valid until the next
  /// change; take [entries] to keep a stable list.
  Iterable<LogEntry> get view => _LogView(this);

  /// An independent copy, oldest first.
  List<LogEntry> get entries => List.unmodifiable(view);

  /// Records [message] (redacted, capped) when the log is on and [level]
  /// passes the selected level. Never throws.
  void add(LogLevel level, String message) {
    if (!_enabled || level.index < _level.index) return;
    final entry = LogEntry(
      time: _clock().toUtc(),
      level: level,
      message: _cap(redactor.redactText(message)),
    );
    if (_ring.length < capacity) {
      _ring.add(entry);
    } else {
      _ring[_start] = entry;
      _start = (_start + 1) % capacity;
    }
    _changed();
  }

  static String _cap(String m) {
    if (m.length <= maxMessageLength) return m;
    var end = maxMessageLength - truncationMarker.length;
    final unit = m.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    return '${m.substring(0, end)}$truncationMarker';
  }

  void clear() {
    if (_ring.isEmpty) return;
    _drop();
    _changed();
  }

  void _drop() {
    _ring.clear();
    _start = 0;
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _changed() {
    _version++;
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

class _LogView extends Iterable<LogEntry> {
  const _LogView(this._log);

  final DiagnosticsLog _log;

  @override
  int get length => _log.length;

  @override
  bool get isEmpty => _log.length == 0;

  @override
  LogEntry elementAt(int index) => _log.entryAt(index);

  @override
  Iterator<LogEntry> get iterator => _LogIterator(_log);
}

class _LogIterator implements Iterator<LogEntry> {
  _LogIterator(this._log);

  final DiagnosticsLog _log;
  int _i = -1;

  @override
  LogEntry get current => _log.entryAt(_i);

  @override
  bool moveNext() {
    if (_i + 1 >= _log.length) return false;
    _i++;
    return true;
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
  const DiagnosticsBundle._(this.sections, this.text, this.logIsEmpty);

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
    return DiagnosticsBundle._(
      List.unmodifiable(sections),
      text,
      entries.isEmpty,
    );
  }

  final List<DiagnosticsSection> sections;
  final String text;

  /// The log section has no lines (the log is off or empty).
  final bool logIsEmpty;

  /// A short summary for a pre-filled issue: every section except the log.
  /// The full [text] travels as a shared file, never in an address.
  String get summaryText => [
    'Consolarr diagnostics',
    for (final section in sections)
      if (section.id != 'log') '## ${section.title}\n${section.body}',
  ].join('\n\n');

  /// UTF-8 bytes of [text]: exactly what the share sheet receives.
  List<int> get bytes => utf8.encode(text);
}

/// Builds the pre-filled GitHub "new issue" address. The app never contacts
/// GitHub: the address is opened in the browser on an explicit tap.
abstract final class GithubIssueLink {
  /// Browsers and GitHub accept long addresses, but proxies do not; stay well
  /// below the common 8 KB limit.
  static const maxUrlLength = 6000;

  /// The only host an issue address may point to.
  static const expectedHost = 'github.com';

  static Uri build({
    required Uri repository,
    required String title,
    required String body,
    String truncationNote = '[truncated: attach the shared file]',
  }) {
    // Exactly https://github.com: the app never builds an address for any
    // other host (a look-alike host or a plain-http address is refused).
    if (repository.scheme != 'https' || repository.host != expectedHost) {
      throw ArgumentError.value(
        repository,
        'repository',
        'must be https://$expectedHost',
      );
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
