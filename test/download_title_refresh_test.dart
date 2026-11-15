import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/episode.dart';
import 'package:read_book/models/read_mark.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/download_refresh_runner.dart';
import 'package:read_book/services/narou_api_client.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  late Directory directory;
  late Box<Download> downloads;
  late Box<ReadMark> readMarks;
  late Work work;
  late _TitleClient client;
  late NovelRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'read_book_title_refresh_test_',
    );
    Hive.init(directory.path);

    final workAdapter = WorkAdapter();
    if (!Hive.isAdapterRegistered(workAdapter.typeId)) {
      Hive.registerAdapter(workAdapter);
    }
    final downloadAdapter = DownloadAdapter();
    if (!Hive.isAdapterRegistered(downloadAdapter.typeId)) {
      Hive.registerAdapter(downloadAdapter);
    }
    final readAdapter = ReadMarkAdapter();
    if (!Hive.isAdapterRegistered(readAdapter.typeId)) {
      Hive.registerAdapter(readAdapter);
    }

    final works = await Hive.openBox<Work>('works');
    downloads = await Hive.openBox<Download>('downloads');
    readMarks = await Hive.openBox<ReadMark>('read_marks');

    work = Work(
      workId: 'n3380le',
      siteIndex: Site.narou.index,
      title: '作品',
      author: '作者',
      genre: '',
      summary: '',
      totalEpisodeCount: 2,
      checkedEpisodeCount: 2,
      lastUpdatedAt: DateTime(2026),
      isCompleted: false,
      authorId: '',
      keyword: '',
    );
    await works.put(work.workId, work);

    for (var number = 1; number <= 2; number++) {
      await downloads.put(
        'n3380le_$number',
        Download(
          workId: work.workId,
          episodeNo: number,
          episodeTitle: '旧タイトル$number',
          body: '保存済み本文$number',
          downloadedAt: DateTime(2026),
          publishedAt: '保存済み掲載日',
          sourceId: 'https://ncode.syosetu.com/n3380le/$number/',
          sourceUpdatedAt: 'same-version',
        ),
      );
    }

    await readMarks.put(
      'n3380le_1',
      ReadMark(workId: work.workId, episodeNo: 1, readAt: DateTime(2026)),
    );

    client = _TitleClient();
    repository = NovelRepository(
      narouApiClient: client,
      downloadRefreshRunner: DownloadRefreshRunner(interval: Duration.zero),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('本文を取得せずタイトルだけ変更し、本文関連情報と既読を維持', () async {
    final original = downloads.get('n3380le_1')!;
    final readAt = readMarks.get('n3380le_1')!.readAt;

    final result = await repository.refreshDownloadedWork(work: work);

    final updated = downloads.get('n3380le_1')!;
    expect(result.updatedCount, 0);
    expect(result.titleUpdatedCount, 2);
    expect(result.unchangedCount, 0);
    expect(updated.episodeTitle, '新タイトル1');
    expect(updated.body, '保存済み本文1');
    expect(updated.downloadedAt, DateTime(2026));
    expect(updated.publishedAt, '保存済み掲載日');
    expect(updated.sourceUpdatedAt, 'same-version');
    expect(updated.sourceId, original.sourceId);
    expect(original.episodeTitle, '旧タイトル1');
    expect(readMarks.get('n3380le_1')!.readAt, readAt);

    await downloads.close();
    downloads = await Hive.openBox<Download>('downloads');
    expect(downloads.get('n3380le_1')!.episodeTitle, '新タイトル1');
  });

  test('同じタイトルは更新不要として集計する', () async {
    client.titlePrefix = '旧タイトル';

    final result = await repository.refreshDownloadedWork(work: work);

    expect(result.titleUpdatedCount, 0);
    expect(result.unchangedCount, 2);
  });

  test('空タイトルで保存済みタイトルを消さない', () async {
    client.emptyTitles = true;

    final result = await repository.refreshDownloadedWork(work: work);

    expect(result.unchangedCount, 2);
    expect(downloads.get('n3380le_1')!.episodeTitle, '旧タイトル1');
  });

  test('識別子不一致の話のタイトルを変更しない', () async {
    client.mismatchFirst = true;

    final result = await repository.refreshDownloadedWork(work: work);

    expect(result.skippedCount, 1);
    expect(result.titleUpdatedCount, 1);
    expect(downloads.get('n3380le_1')!.episodeTitle, '旧タイトル1');
  });

  test('識別子のない旧データのタイトルを推測で更新しない', () async {
    final first = downloads.get('n3380le_1')!;
    first.sourceId = '';
    await first.save();

    final result = await repository.refreshDownloadedWork(work: work);

    expect(result.skippedCount, 1);
    expect(result.titleUpdatedCount, 1);
    expect(downloads.get('n3380le_1')!.episodeTitle, '旧タイトル1');
  });

  test('順番待ち中に変わった話はタイトルも上書きしない', () async {
    final result = await repository.refreshDownloadedWork(
      work: work,
      onProgress: (completed, total) {
        if (completed == 1) {
          // 同じHiveオブジェクトへの変更もスナップショット比較で検出。
          downloads.get('n3380le_2')!.episodeTitle = '別処理のタイトル';
        }
      },
    );

    expect(result.titleUpdatedCount, 1);
    expect(result.skippedCount, 1);
    expect(downloads.get('n3380le_2')!.episodeTitle, '別処理のタイトル');
  });
}

class _TitleClient extends NarouApiClient {
  String titlePrefix = '新タイトル';
  bool emptyTitles = false;
  bool mismatchFirst = false;

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(String ncode) async {
    return [
      for (var number = 1; number <= 2; number++)
        {
          'episodeNo': number.toString(),
          'title': emptyTitles ? '   ' : '$titlePrefix$number',
          'publishedAt': '目次にある別の掲載日',
          'sourceId': mismatchFirst && number == 1
              ? 'https://ncode.syosetu.com/n3380le/99/'
              : 'https://ncode.syosetu.com/n3380le/$number/',
          'sourceUpdatedAt': 'same-version',
        },
    ];
  }

  @override
  Future<Episode> fetchEpisodeBodyForRefresh({
    required String workId,
    required int episodeNo,
    required String episodeTitle,
    required String sourceId,
  }) async {
    throw StateError('タイトルだけの更新で本文を取得してはいけません。');
  }
}
