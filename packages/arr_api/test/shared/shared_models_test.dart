// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:test/test.dart';

ArrQueueItem _q(Map<String, Object?> j) =>
    ArrQueueItem.fromJson({'id': 1, 'title': 'Example.Show', ...j});

void main() {
  group('ArrQueueItem state', () {
    final table = <String, (Map<String, Object?>, ArrQueueState)>{
      'downloading': ({'status': 'downloading'}, ArrQueueState.downloading),
      'paused': ({'status': 'paused'}, ArrQueueState.paused),
      'queued': ({'status': 'queued'}, ArrQueueState.queued),
      'delay': ({'status': 'delay'}, ArrQueueState.delayed),
      'completed': ({'status': 'completed'}, ArrQueueState.completed),
      'failed': ({'status': 'failed'}, ArrQueueState.downloadFailed),
      'client unavailable': (
        {'status': 'downloadClientUnavailable'},
        ArrQueueState.clientUnavailable,
      ),
      'import pending': (
        {'status': 'completed', 'trackedDownloadState': 'importPending'},
        ArrQueueState.importPending,
      ),
      'importing': (
        {'status': 'completed', 'trackedDownloadState': 'importing'},
        ArrQueueState.importing,
      ),
      'import failed': (
        {'status': 'completed', 'trackedDownloadState': 'importFailed'},
        ArrQueueState.importFailed,
      ),
      'download failed': (
        {'status': 'downloading', 'trackedDownloadState': 'downloadFailed'},
        ArrQueueState.downloadFailed,
      ),
      'warning': (
        {'status': 'unknown', 'trackedDownloadStatus': 'warning'},
        ArrQueueState.warning,
      ),
      'error status': (
        {'status': 'unknown', 'trackedDownloadStatus': 'error'},
        ArrQueueState.warning,
      ),
      'unknown': ({'status': 'something-new'}, ArrQueueState.unknown),
      'missing status': (<String, Object?>{}, ArrQueueState.unknown),
    };
    for (final e in table.entries) {
      test(e.key, () => expect(_q(e.value.$1).state, e.value.$2));
    }
  });

  group('ArrQueueItem fields', () {
    test('v3 and v4 shapes, messages, embedded series and episode', () {
      final item = _q({
        'status': 'downloading',
        'size': 1000,
        'sizeleft': 250,
        'timeleft': '00:10:05',
        'protocol': 'torrent',
        'downloadClient': 'Example Client',
        'downloadId': 'ABCDEF0123456789',
        'indexer': 'Example Indexer',
        'seriesId': 7,
        'episodeId': 3,
        'seasonNumber': 2,
        'statusMessages': [
          {
            'title': 'Example.Show',
            'messages': ['No files found', '', 5],
          },
          'junk',
        ],
        'quality': {
          'quality': {'name': 'WEBDL-1080p'},
        },
        'series': {'title': 'Example Show'},
        'episode': {'title': 'Pilot', 'episodeNumber': 4},
        'unknown': 1,
      });
      expect(item.progress, closeTo(0.75, 1e-9));
      expect(item.timeLeft, const Duration(minutes: 10, seconds: 5));
      expect(item.protocol, ArrProtocol.torrent);
      expect(item.messages.single.messages, ['No files found']);
      expect(item.hasWarnings, isTrue);
      expect(item.qualityName, 'WEBDL-1080p');
      expect(item.mediaTitle, 'Example Show');
      expect(item.episodeNumber, 4);
      expect(item.downloadId, 'ABCDEF0123456789');
      expect(item.seasonNumber, 2);
    });

    test('sizeleft larger than size is clamped; negatives are zero', () {
      final a = _q({'size': 100, 'sizeleft': 500});
      expect(a.sizeLeft, 100);
      expect(a.progress, 0);
      final b = _q({'size': -5, 'sizeleft': -1});
      expect(b.size, 0);
      expect(b.progress, 0);
    });

    test('missing optional fields are tolerated; id is required', () {
      final item = ArrQueueItem.fromJson({'id': 2});
      expect(item.title, '');
      expect(item.timeLeft, isNull);
      expect(item.hasWarnings, isFalse);
      expect(
        () => ArrQueueItem.fromJson({'title': 'x'}),
        throwsFormatException,
      );
      expect(() => ArrQueueItem.fromJson({'id': 'x'}), throwsFormatException);
    });

    test('toString carries no title', () {
      expect(_q({}).toString(), isNot(contains('Example')));
    });
  });

  group('parseArrTimeSpan', () {
    test('formats', () {
      expect(parseArrTimeSpan('00:10:00'), const Duration(minutes: 10));
      expect(
        parseArrTimeSpan('1.02:03:04'),
        const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
      );
      expect(
        parseArrTimeSpan('01:02:03.1234567'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
    });
    test('garbage is null', () {
      for (final v in [null, '', 'soon', '12:00', '-00:10:00']) {
        expect(parseArrTimeSpan(v), isNull, reason: '$v');
      }
    });
  });

  group('ArrCommand', () {
    test('terminal logic', () {
      ArrCommand c(String s) => ArrCommand.fromJson({'id': 1, 'status': s});
      for (final s in ['queued', 'started', 'what']) {
        expect(c(s).isTerminal, isFalse, reason: s);
      }
      for (final s in [
        'completed',
        'failed',
        'aborted',
        'cancelled',
        'orphaned',
      ]) {
        expect(c(s).isTerminal, isTrue, reason: s);
      }
      expect(c('Completed').isSuccess, isTrue);
      expect(c('failed').isSuccess, isFalse);
      expect(c('what').status, ArrCommandStatus.unknown);
    });
    test('toString has no name or message', () {
      final c = ArrCommand.fromJson({
        'id': 3,
        'status': 'queued',
        'name': 'Secret Title',
        'message': 'Secret',
      });
      expect(c.toString(), 'ArrCommand(3, queued)');
    });
    test('request JSON merges name and params', () {
      expect(
        const ArrCommandRequest('SeriesSearch', {'seriesId': 2}).toJson(),
        {'name': 'SeriesSearch', 'seriesId': 2},
      );
    });
  });

  group('ArrRelease', () {
    test('v4 shape: ageMinutes, custom formats, languages, rejections', () {
      final r = ArrRelease.fromJson({
        'guid': 'g',
        'title': 'Example.Show.S01E01',
        'indexerId': 2,
        'indexer': 'Example Indexer',
        'size': 1000,
        'ageMinutes': 90,
        'seeders': 12,
        'protocol': 'usenet',
        'quality': {
          'quality': {
            'name': 'Bluray-1080p',
            'resolution': 1080,
            'source': 'bluray',
          },
        },
        'approved': false,
        'rejections': ['Not wanted', ''],
        'downloadAllowed': false,
        'customFormats': [
          {'name': 'HDR'},
          {'name': ''},
        ],
        'languages': [
          {'name': 'English'},
        ],
        'extra': true,
      });
      expect(r.ageMinutes, 90);
      expect(r.protocol, ArrProtocol.usenet);
      expect(r.resolution, 1080);
      expect(r.isRejected, isTrue);
      expect(r.rejections, ['Not wanted']);
      expect(r.customFormats, ['HDR']);
      expect(r.languages, ['English']);
      expect(r.downloadAllowed, isFalse);
    });

    test('v3 shape: age in days, approved derived from rejections', () {
      final ok = ArrRelease.fromJson({'guid': 'g', 'age': 2});
      expect(ok.ageMinutes, 2 * 24 * 60);
      expect(ok.isRejected, isFalse);
      final bad = ArrRelease.fromJson({
        'guid': 'g',
        'rejections': ['Too big'],
      });
      expect(bad.isRejected, isTrue);
      expect(bad.approved, isFalse);
    });

    test('negative size is zero; guid is required; no title in toString', () {
      expect(ArrRelease.fromJson({'guid': 'g', 'size': -1}).size, 0);
      expect(() => ArrRelease.fromJson({'title': 'x'}), throwsFormatException);
      final r = ArrRelease.fromJson({'guid': 'g', 'title': 'Secret'});
      expect(r.toString(), isNot(contains('Secret')));
    });
  });

  group('ArrPage', () {
    test('parses records and counts skipped', () {
      final p = ArrPage.fromJson<int>({
        'page': 1,
        'pageSize': 2,
        'totalRecords': 5,
        'records': [
          {'id': 1},
          'bad',
        ],
      }, (j) => j['id']! as int);
      expect(p.records, [1]);
      expect(p.skipped, 1);
      expect(p.hasMore, isTrue);
    });
    test('non-object throws', () {
      expect(() => ArrPage.fromJson<int>([], (j) => 1), throwsFormatException);
    });
  });
}
