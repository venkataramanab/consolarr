// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:observability/src/events/catalog.dart';
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
/// process ends. Messages are redacted and scrubbed once at write time (by
/// [add], or by [AppLogger] before [addScrubbed]) and capped at
/// [maxMessageLength]; the bundle scrubs them again with the known server
/// values.
///
/// Reading does not copy: [length], [entryAt] and [view] look straight into the
/// buffer, and [version] changes on every change so a listener can tell
/// whether to rebuild. [entries] is the explicit (copying) snapshot used by
/// the bundle.
class DiagnosticsLog {
  DiagnosticsLog({
    this.capacity = 500,
    this.redactor = const Redactor(),
    DiagnosticsScrubber? scrubber,
    DateTime Function()? clock,
  }) : scrubber = scrubber ?? const DiagnosticsScrubber(),
       assert(capacity > 0, 'capacity > 0'),
       _clock = clock ?? DateTime.now;

  /// Largest stored message, marker included (about 1 KB).
  static const maxMessageLength = 1024;

  /// Appended to a message that was cut at [maxMessageLength].
  static const truncationMarker = ' ...[TRUNCATED]';

  final int capacity;
  final Redactor redactor;

  /// The stricter pass applied to every line at write time (hosts, addresses,
  /// paths, quoted titles, passkeys), so the log view only ever shows
  /// scrubbed text. The bundle scrubs again, with the known server values.
  final DiagnosticsScrubber scrubber;
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
  void add(LogLevel level, String message) =>
      _store(level, scrubber.scrub(redactor.redactText(message)));

  /// Records a line that has **already** been through the redactor and the
  /// scrubber (it is [AppLogger]'s output, which scrubs once for every sink
  /// it feeds). Anything else must use [add].
  void addScrubbed(LogLevel level, String scrubbed) => _store(level, scrubbed);

  void _store(LogLevel level, String text) {
    if (!_enabled || level.index < _level.index) return;
    final entry = LogEntry(
      time: _clock().toUtc(),
      level: level,
      message: _cap(text),
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

  /// `\\server\share\dir\file name.mkv` (also `\\?\UNC\...`): the host,
  /// the share and every folder name leak, and the parts may contain spaces.
  /// With an extension the match ends there; without one it runs to the end of
  /// the line or the closing quote, since where a folder name ends is unknown.
  static final _uncExt = RegExp(
    r'\\\\[^\\\s"]+\\[^\r\n"]*?\.[A-Za-z0-9]{2,5}\b',
  );
  static final _unc = RegExp(r'\\\\[^\\\s"]+(?:\\[^\r\n"]*)?');

  /// `//server/share/...` (an SMB URL without a scheme).
  static final _slashUnc = RegExp(r'(?<![\w:/.])//[^/\s"]+(?:/[^\r\n"]*)?');
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

  /// Returns [line] with everything above removed. Idempotent: the passes
  /// repeat until the text stops changing (a replacement can change how
  /// quotes pair up, so one pass is not always enough), at most
  /// [_maxPasses] times.
  String scrub(String line) {
    var out = line;
    for (var i = 0; i < _maxPasses; i++) {
      final next = _pass(out);
      if (next == out) break;
      out = next;
    }
    return out;
  }

  static const _maxPasses = 6;

  /// Removes [knownValues] from the text *between* existing placeholders only.
  /// A value such as "ted" or "act" is a substring of `[REDACTED]`, and
  /// replacing inside a placeholder would corrupt it into
  /// `[REDAC[REDACTED]]`, leak the shape of what was removed and grow on every
  /// pass. Splitting on the placeholder first keeps it intact.
  String _scrubKnown(String line) {
    final values = [
      for (final v in knownValues)
        if (v.length >= 3) v,
    ]..sort((a, b) => b.length.compareTo(a.length));
    if (values.isEmpty) return line;
    // One alternation, one scan: replacing value by value would rescan the
    // placeholders the earlier values just inserted.
    final any = RegExp(
      values.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    return line.split(_mark).map((p) => p.replaceAll(any, _mark)).join(_mark);
  }

  String _pass(String line) {
    var out = _scrubKnown(line);
    out = out.replaceAll(_magnet, _mark);
    out = redactor.redactText(out);
    out = out.replaceAll(_url, _mark);
    out = out.replaceAll(_uncExt, _mark).replaceAll(_unc, _mark);
    out = out.replaceAll(_slashUnc, _mark);
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

/// Which build this is (closed set, so nothing else can be reported).
enum AppFlavor { foss, play }

/// How the services of one kind are doing, as shown in the bundle. A closed
/// set: the bundle can say nothing else about a server's state.
enum ServiceHealthBucket {
  /// No check has run (the bundle never starts one).
  notChecked,
  checking,

  /// Some servers of the kind were checked, others were not.
  partial,
  healthy,
  degraded,
  unauthorized,
  unreachable;

  /// The English words used in the bundle.
  String get label => switch (this) {
    notChecked => 'not checked',
    checking => 'checking',
    partial => 'partly checked',
    healthy => 'healthy',
    degraded => 'degraded',
    unauthorized => 'unauthorized',
    unreachable => 'unreachable',
  };
}

/// The connection health of every server of one [kind]. Only closed values
/// and counts: a server name, host, port or id cannot be carried.
class DiagnosticsServiceEntry {
  const DiagnosticsServiceEntry({
    required this.kind,
    required this.servers,
    required this.health,
    this.majorVersion,
    this.cleartextOptIn = false,
  });

  final ServiceKindParam kind;

  /// Number of configured servers of this kind.
  final int servers;
  final ServiceHealthBucket health;

  /// The server's major version when a check reported it.
  final int? majorVersion;

  /// At least one server of this kind has plain http opted in.
  final bool cleartextOptIn;

  String get line =>
      '${kind.code}: servers=$servers, health=${health.label}, '
      'major=${majorVersion ?? 'unknown'}, '
      'cleartext=${cleartextOptIn ? 'yes' : 'no'}';
}

/// Facts about the install that go in the bundle. No identity.
class DiagnosticsInfo {
  const DiagnosticsInfo({
    required this.appVersion,
    required this.buildMode,
    required this.platform,
    required this.locale,
    this.flavor = AppFlavor.foss,
    this.crashReportsConsent = false,
    this.analyticsConsent = false,
  });

  final AppFlavor flavor;

  /// The state of the two consent switches.
  final bool crashReportsConsent;
  final bool analyticsConsent;

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

/// Marks a section body that was cut to fit the size cap.
const _cutMarker = ' [cut]';

/// [text] cut to at most [maxBytes] UTF-8 bytes, on a character boundary.
String _cutBytes(String text, int maxBytes) {
  if (maxBytes <= 0) return '';
  var bytes = 0;
  final out = StringBuffer();
  for (final rune in text.runes) {
    final w = rune < 0x80 ? 1 : (rune < 0x800 ? 2 : (rune < 0x10000 ? 3 : 4));
    if (bytes + w > maxBytes) break;
    bytes += w;
    out.writeCharCode(rune);
  }
  return out.toString();
}

/// Cuts the longest section bodies (never a heading) until the text fits.
List<DiagnosticsSection> _shrinkToFit(
  List<DiagnosticsSection> sections,
  String Function(List<DiagnosticsSection>) textOf,
  int maxBytes,
) {
  var current = sections;
  final marker = utf8.encode(_cutMarker).length;
  while (true) {
    final over = utf8.encode(textOf(current)).length - maxBytes;
    if (over <= 0) return current;
    var index = -1;
    var longest = marker;
    for (var i = 0; i < current.length; i++) {
      final n = utf8.encode(current[i].body).length;
      if (n > longest) {
        longest = n;
        index = i;
      }
    }
    if (index < 0) return current; // nothing left to cut
    final cut = _cutBytes(current[index].body, longest - over - marker);
    final s = current[index];
    current = [
      for (var i = 0; i < current.length; i++)
        if (i == index)
          DiagnosticsSection(id: s.id, title: s.title, body: '$cut$_cutMarker')
        else
          current[i],
    ];
  }
}

/// The redacted diagnostics bundle (SET-04). [text] is what the preview shows,
/// what the shared file contains byte for byte ([bytes]) and what the GitHub
/// issue body is built from. Nothing outside the sections is included.
class DiagnosticsBundle {
  const DiagnosticsBundle._(this.sections, this.text, this.logIsEmpty);

  /// Section titles are English: the bundle is read by maintainers.
  ///
  /// With [maxBytes] the log section keeps only the newest entries that fit,
  /// so [text] (what the preview shows and what is shared) never exceeds it
  /// in UTF-8 bytes and needs no further cutting.
  factory DiagnosticsBundle.build({
    required DiagnosticsInfo info,
    required List<String> errorCategories,
    required List<LogEntry> entries,
    List<DiagnosticsServiceEntry> services = const [],
    int? maxBytes,
    DiagnosticsScrubber scrubber = const DiagnosticsScrubber(),
  }) {
    String s(String v) => scrubber.scrub(v);
    // Every line is scrubbed once; trimming only joins fewer of them.
    final lines = [
      for (final e in entries)
        '${e.time.toIso8601String()} '
            '${e.level.name.toUpperCase()} ${s(e.message)}',
    ];

    int bytesOf(String v) => utf8.encode(v).length;

    String noteFor(int omitted) =>
        '($omitted older entries left out to keep the text '
        'within the size limit)';

    String logBody(int keep) {
      if (lines.isEmpty) return '(empty)';
      final omitted = lines.length - keep;
      return [
        if (omitted > 0) noteFor(omitted),
        ...lines.skip(omitted),
      ].join('\n');
    }

    List<DiagnosticsSection> sectionsWith(String log) => [
      DiagnosticsSection(
        id: 'app',
        title: 'App',
        body:
            'version: ${s(info.appVersion)}\nbuild: ${s(info.buildMode)}\n'
            'flavor: ${info.flavor.name}\n'
            'crash reports: ${info.crashReportsConsent ? 'on' : 'off'}\n'
            'usage analytics: ${info.analyticsConsent ? 'on' : 'off'}',
      ),
      DiagnosticsSection(
        id: 'platform',
        title: 'Platform',
        body: s(info.platform),
      ),
      DiagnosticsSection(id: 'locale', title: 'Locale', body: s(info.locale)),
      DiagnosticsSection(
        id: 'services',
        title: 'Services',
        body: services.isEmpty
            ? '(none configured)'
            : services.map((e) => e.line).join('\n'),
      ),
      DiagnosticsSection(
        id: 'error_categories',
        title: 'Error categories',
        body: errorCategories.isEmpty
            ? '(none)'
            : errorCategories.map(s).join('\n'),
      ),
      DiagnosticsSection(id: 'log', title: 'Log', body: log),
    ];

    String textOf(List<DiagnosticsSection> sections) => [
      'Consolarr diagnostics',
      for (final section in sections) '## ${section.title}\n${section.body}',
    ].join('\n\n');

    var sections = sectionsWith(logBody(lines.length));
    var text = textOf(sections);
    if (maxBytes != null && bytesOf(text) > maxBytes) {
      // The log is the last section, so the text is the same fixed part plus
      // the log body, and the size of the body for any number of kept lines
      // is plain arithmetic. It is NOT monotonic in that number (the note of
      // omitted entries changes width, and a short line can weigh less than
      // the note), so the largest suffix that fits is found by scanning, not
      // by bisection.
      final fixed = bytesOf(textOf(sectionsWith('')));
      final lineBytes = [for (final l in lines) bytesOf(l)];
      var suffix = 0; // bytes of the newest `keep` lines
      var keep = -1;
      final noteWidth = <int>[];
      for (var k = 0; k <= lines.length; k++) {
        noteWidth.add(
          k == lines.length ? 0 : bytesOf(noteFor(lines.length - k)),
        );
      }
      for (var k = 0; k < lines.length; k++) {
        // k = how many of the newest lines are kept (0..n-1).
        if (k > 0) suffix += lineBytes[lines.length - k];
        final items = k + 1; // the note counts as one item
        final body = suffix + noteWidth[k] + (items - 1);
        if (fixed + body <= maxBytes) keep = k;
      }
      if (keep >= 0) {
        sections = sectionsWith(logBody(keep));
        text = textOf(sections);
      } else {
        sections = _shrinkToFit(sectionsWith(logBody(0)), textOf, maxBytes);
        text = textOf(sections);
      }
      if (bytesOf(text) > maxBytes) {
        // The headings alone are over the cap: cut the text itself, so what
        // is shown and what is shared still cannot exceed it.
        text = _cutBytes(text, maxBytes);
      }
    }
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
