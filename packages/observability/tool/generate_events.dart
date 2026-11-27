// SPDX-License-Identifier: GPL-3.0-or-later

// Regenerates lib/src/events/catalog.dart from events/*.yaml.
// Usage (repo root): dart run packages/observability/tool/generate_events.dart

import 'dart:io';

import 'src/event_generator.dart';

void main() {
  final root = _packageRoot();
  final yamls = <String, String>{
    for (final f in Directory('${root.path}/events').listSync())
      if (f is File && f.path.endsWith('.yaml'))
        f.uri.pathSegments.last: f.readAsStringSync(),
  };
  final source = formatWithDart(
    generateCatalog(yamls),
    scratchDir: Directory.systemTemp.createTempSync('events').path,
  );
  File('${root.path}/lib/src/events/catalog.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(source);
}

Directory _packageRoot() {
  final script = File.fromUri(Platform.script).parent.parent;
  return script;
}
