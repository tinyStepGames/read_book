import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download_job.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/screens/work_detail_screen.dart';
import 'package:read_book/services/download_manager.dart';
import 'package:read_book/services/novel_repository.dart';

class _RecordingRepository extends NovelRepository {
  List<Map<String, String>> entries = [];
  final calls = <Map<String, String>>[];
  final downloaded = <int>{};

  @override
  Future<void> refreshWorkDetails(Work work) async {}

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(Work work) async {
    return entries.map((entry) => Map<String, String>.of(entry)).toList();
  }

  @override
  Future<void> updateDownloadPublishedDates({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {}

  @override
  bool hasAnyDownload(String workId) => downloaded.isNotEmpty;

  @override
  bool isDownloaded(Work work, int episodeNo) => downloaded.contains(episodeNo);

  @override
  bool isEpisodeRead(String workId, int episodeNo) => false;

  @override
  Future<void> downloadEpisode({
    required Work work,
    required int episodeNo,
    required String episodeTitle,
    String publishedAt = '',
    String sourceId = '',
    String sourceUpdatedAt = '',
  }) async {
    calls.add({
      'workId': work.workId,
      'episodeNo': '$episodeNo',
      'title': episodeTitle,
      'publishedAt': publishedAt,
      'sourceId': sourceId,
      'sourceUpdatedAt': sourceUpdatedAt,
    });
    downloaded.add(episodeNo);
  }
}

Work createWork(Site site) {
  return Work(
    workId: site == Site.narou ? 'n3380le' : '2912051605992818100',
    siteIndex: site.index,
    title: '画面テスト作品',
    author: 'テスト作者',
    genre: '',
    summary: '',
    totalEpisodeCount: 1,
    checkedEpisodeCount: 1,
    lastUpdatedAt: DateTime.utc(2026, 1, 1),
    isCompleted: false,
  );
}

void main() {
  group('作品詳細画面の単話ダウンロード', () {
    late Directory directory;
    late _RecordingRepository repository;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp(
        'work_detail_download_metadata_test_',
      );
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(6)) {
        Hive.registerAdapter(DownloadJobAdapter());
      }
      await Hive.openBox<DownloadJob>('download_jobs');

      // 同一テストファイルでは、singletonが保持するRepositoryを共用します。
      repository = _RecordingRepository();
      DownloadManager.init(repository);
    });

    setUp(() {
      repository.entries = [];
      repository.calls.clear();
      repository.downloaded.clear();
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    for (final site in [Site.narou, Site.kakuyomu]) {
      testWidgets('${site.name}の同期情報を画面から渡す', (tester) async {
        final work = createWork(site);
        final sourceId = site == Site.narou
            ? 'https://ncode.syosetu.com/n3380le/1/'
            : '2912051606897546666';
        const stamp = '2026-11-15T03:00:00.000Z';

        repository.entries = [
          {
            'episodeNo': '1',
            'title': 'テスト第1話',
            'publishedAt': '2026/11/01 12:00',
            'sourceId': sourceId,
            'sourceUpdatedAt': stamp,
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: WorkDetailScreen(repository: repository, work: work),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('テスト第1話'), findsOneWidget);
        expect(find.byIcon(Icons.download_outlined), findsOneWidget);

        await tester.tap(find.byIcon(Icons.download_outlined));
        await tester.pumpAndSettle();

        expect(repository.calls, hasLength(1));
        expect(repository.calls.single, {
          'workId': work.workId,
          'episodeNo': '1',
          'title': 'テスト第1話',
          'publishedAt': '2026/11/01 12:00',
          'sourceId': sourceId,
          'sourceUpdatedAt': stamp,
        });
        expect(find.byIcon(Icons.download_done), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('旧形式の目次では空の同期情報を渡す', (tester) async {
      repository.entries = [
        {'episodeNo': '1', 'title': '旧形式の第1話', 'update': '2026/11/01 12:00'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: WorkDetailScreen(
            repository: repository,
            work: createWork(Site.narou),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();

      expect(repository.calls, hasLength(1));
      expect(repository.calls.single['publishedAt'], '2026/11/01 12:00');
      expect(repository.calls.single['sourceId'], '');
      expect(repository.calls.single['sourceUpdatedAt'], '');
      expect(find.byIcon(Icons.download_done), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }, skip: Platform.isIOS);
}
