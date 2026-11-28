// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/add_torrent_controller.dart';
import 'package:consolarr/features/torrents/application/torrent_link.dart';
import 'package:consolarr/features/torrents/presentation/add_torrent_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

const _hash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _magnet = 'magnet:?xt=urn:btih:$_hash&dn=Example+Linux+ISO';
const _passkeyMagnet =
    'magnet:?xt=urn:btih:$_hash&dn=Example&tr=https%3A%2F%2Ftracker.example%2Fa%3Fpasskey%3Dsecret-passkey';

PickedTorrentFile _file(String name, List<int> bytes, {int? length}) =>
    PickedTorrentFile(
      name: name,
      length: () async => length ?? bytes.length,
      readBytes: () async => Uint8List.fromList(bytes),
    );

List<int> _torrentBytes() => 'd4:infod4:name3:abcee'.codeUnits;

Future<FakeTorrentClient> _pump(
  WidgetTester tester, {
  FakeTorrentClient? client,
  HarnessVariant variant = baseVariant,
  List<PickedTorrentFile> picks = const [],
}) async {
  final c = client ?? FakeTorrentClient();
  applyVariantView(tester, variant);
  await tester.pumpWidget(
    sheetApp(
      variant,
      const AddTorrentSheet(),
      client: c,
      overrides: [
        torrentFilePickerProvider.overrideWithValue(() async => picks),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Finder get _link => find.byType(TextField).first;

void main() {
  testWidgets('empty: nothing sendable, no error shown', (tester) async {
    await _pump(tester);
    expect(find.text('Add'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
          .onPressed,
      isNull,
    );
    expect(find.text('Use a magnet link or an http(s) address.'), findsNothing);
  });

  testWidgets('invalid links say why', (tester) async {
    await _pump(tester);
    await tester.enterText(_link, 'ftp://files.example/a.torrent');
    await tester.pump();
    expect(
      find.text('Use a magnet link or an http(s) address.'),
      findsOneWidget,
    );
    await tester.enterText(_link, 'magnet:?xt=urn:btih:nope');
    await tester.pump();
    expect(
      find.text('This magnet link has no valid info hash.'),
      findsOneWidget,
    );
    await tester.enterText(_link, 'https://user:pw@files.example/a.torrent');
    await tester.pump();
    expect(
      find.text('Addresses with a username or password are not accepted.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a valid magnet shows the parsed name before anything is sent', (
    tester,
  ) async {
    final c = await _pump(tester);
    await tester.enterText(_link, _magnet);
    await tester.pump();
    expect(find.text('Add “Example Linux ISO”?'), findsOneWidget);
    expect(c.addedLinks, isEmpty);
  });

  testWidgets('a URL shows its host only, never the query', (tester) async {
    await _pump(tester);
    await tester.enterText(
      _link,
      'https://files.example/a.torrent?passkey=secret-passkey',
    );
    await tester.pump();
    expect(find.text('Torrent file from files.example'), findsOneWidget);
    expect(
      find.textContaining('secret-passkey', findRichText: true),
      findsOneWidget,
    ); // only in the field
  });

  testWidgets('adding: in progress, then added; the field is cleared', (
    tester,
  ) async {
    final c = FakeTorrentClient()..actionGate = Completer<void>();
    await _pump(tester, client: c);
    await tester.enterText(_link, _passkeyMagnet);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Adding…'), findsOneWidget);
    c.actionGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Added to your client.'), findsOneWidget);
    expect(c.addedLinks, [_passkeyMagnet]);
    expect(tester.widget<TextField>(_link).controller!.text, isEmpty);
  });

  testWidgets('failed with a reason; nothing is retried by itself', (
    tester,
  ) async {
    final c = FakeTorrentClient()
      ..actionError = const AppError(ErrorCategory.timeout);
    await _pump(tester, client: c);
    await tester.enterText(_link, _magnet);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not add the torrent.'), findsOneWidget);
    expect(find.textContaining('Nothing was added twice'), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
    expect(c.calls.where((x) => x == 'addLink'), hasLength(1));
    // The link is still there for a manual retry, and one more tap adds once.
    expect(tester.widget<TextField>(_link).controller!.text, _magnet);
    c.actionError = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(c.calls.where((x) => x == 'addLink'), hasLength(2));
  });

  testWidgets('an unsupported client explains instead of crashing', (
    tester,
  ) async {
    final c = FakeTorrentClient()
      ..actionError = const UnsupportedAction('addMagnetOrUrl');
    await _pump(tester, client: c);
    await tester.enterText(_link, _magnet);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not support that action'), findsOneWidget);
  });

  testWidgets('a second tap while adding does not send twice', (tester) async {
    final c = FakeTorrentClient()..actionGate = Completer<void>();
    await _pump(tester, client: c);
    await tester.enterText(_link, _magnet);
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Add');
    await tester.tap(button);
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Adding…'),
      warnIfMissed: false,
    );
    c.actionGate!.complete();
    await tester.pumpAndSettle();
    expect(c.addedLinks, hasLength(1));
  });

  testWidgets('L2: files picked after the sheet closed are discarded unread', (
    tester,
  ) async {
    final picker = Completer<List<PickedTorrentFile>>();
    final c = FakeTorrentClient();
    final overrides = [
      torrentFilePickerProvider.overrideWithValue(() => picker.future),
    ];
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(
      sheetApp(
        baseVariant,
        const AddTorrentSheet(),
        client: c,
        overrides: overrides,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose .torrent files'));
    await tester.pump();
    // The sheet is closed while the system picker is still open.
    await tester.pumpWidget(
      sheetApp(baseVariant, const SizedBox(), client: c, overrides: overrides),
    );
    await tester.pumpAndSettle();
    var discarded = 0;
    var read = 0;
    picker.complete([
      for (final n in ['a.torrent', 'b.torrent'])
        PickedTorrentFile(
          name: n,
          length: () async => 10,
          readBytes: () async {
            read++;
            return Uint8List.fromList(_torrentBytes());
          },
          discard: () async => discarded++,
        ),
    ]);
    await tester.pumpAndSettle();
    expect(discarded, 2);
    expect(read, 0);
    expect(c.calls, isNot(contains('addFile')));
  });

  testWidgets('files: a per-file summary with reasons', (tester) async {
    final c = await _pump(
      tester,
      picks: [
        _file('one.torrent', _torrentBytes()),
        _file('notes.txt', 'plain text, not bencode'.codeUnits),
        _file('huge.torrent', _torrentBytes(), length: maxTorrentFileBytes + 1),
      ],
    );
    await tester.tap(find.text('Choose .torrent files'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 files added'), findsOneWidget);
    expect(find.text('one.torrent: added'), findsOneWidget);
    expect(
      find.textContaining(
        'notes.txt: failed. This does not look like a torrent file.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('huge.torrent: failed. The file is too large'),
      findsOneWidget,
    );
    expect(c.calls.where((x) => x == 'addFile'), hasLength(1));
  });

  testWidgets('paste reads the clipboard only when the button is tapped', (
    tester,
  ) async {
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          reads++;
          return {'text': _magnet};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester);
    expect(reads, 0);
    await tester.tap(find.byTooltip('Paste'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('Add “Example Linux ISO”?'), findsOneWidget);
  });

  testWidgets('options reach the client', (tester) async {
    final c = await _pump(tester);
    await tester.enterText(_link, _magnet);
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Save path'),
      '/data/example',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Category'), 'iso');
    await tester.enterText(find.widgetWithText(TextField, 'Tags'), 'a, b ,');
    await tester.tap(find.text('Start paused'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final o = c.addedOptions.single;
    expect(o.savePath, '/data/example');
    expect(o.category, 'iso');
    expect(o.tags, ['a', 'b']);
    expect(o.paused, isTrue);
  });

  group('survives the stress matrix', () {
    testWidgets('idle, valid, failed', (tester) async {
      final c = FakeTorrentClient()
        ..actionError = const AppError(ErrorCategory.timeout);
      await pumpMatrix(
        tester,
        (v) => sheetApp(v, const AddTorrentSheet(), client: c),
        variants: stressVariants,
        verify: (v) async {
          await tester.enterText(_link, _magnet);
          await tester.pump();
          await expectAccessible(tester);
          await tester.ensureVisible(find.byType(FilledButton).first);
          await tester.tap(find.byType(FilledButton).first);
          await tester.pumpAndSettle();
          expectNoFrameworkExceptions(tester, context: v.label);
        },
      );
    });
  });
}
