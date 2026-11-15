import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/episode.dart';
import 'package:read_book/models/read_mark.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/download_refresh_runner.dart';
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/services/narou_api_client.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  late Directory directory;
  late Box<Download> downloads;
  late Box<ReadMark> readMarks;
  late Work work;
  late _TestClient client;
  late NovelRepository repository;

  Map<String, String> entry(int number, {String stamp = 'new'}) => {
    'episodeNo': number.toString(),
    'title': '新タイトル$number',
    'sourceId': 'https://ncode.syosetu.com/n3380le/$number/',
    'sourceUpdatedAt': stamp,
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'read_book_work_refresh_test_',
    );
    Hive.init(directory.path);

    final downloadAdapter = DownloadAdapter();
    if (!Hive.isAdapterRegistered(downloadAdapter.typeId)) {
      Hive.registerAdapter(downloadAdapter);
    }
    final workAdapter = WorkAdapter();
    if (!Hive.isAdapterRegistered(workAdapter.typeId)) {
      Hive.registerAdapter(workAdapter);
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
      summary: '元の説明文',
      totalEpisodeCount: 3,
      checkedEpisodeCount: 3,
      lastUpdatedAt: DateTime(2026),
      isCompleted: false,
      authorId: '',
      keyword: '',
    );
    await works.put(work.workId, work);

    for (var number = 1; number <= 3; number++) {
      await downloads.put(
        'n3380le_$number',
        Download(
          workId: work.workId,
          episodeNo: number,
          episodeTitle: '旧タイトル$number',
          body: '旧本文$number',
          downloadedAt: DateTime(2026),
          sourceId: 'https://ncode.syosetu.com/n3380le/$number/',
          sourceUpdatedAt: 'old',
        ),
      );
    }

    await readMarks.put(
      'n3380le_1',
      ReadMark(workId: work.workId, episodeNo: 1, readAt: DateTime(2026)),
    );

    client = _TestClient()..entries = [entry(1), entry(2), entry(3)];
    repository = NovelRepository(
      narouApiClient: client,
      illustrationStorageService: _TestIllustrations(),
      downloadRefreshRunner: DownloadRefreshRunner(interval: Duration.zero),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('目次取得・照合・保存を接続し、既読と作品情報は変えない', () async {
    final readAt = readMarks.get('n3380le_1')!.readAt;

    final result = await repository.refreshDownloadedWork(work: work);

    expect(client.listCalls, 1);
    expect(client.bodyCalls, [1, 2, 3]);
    expect(result.updatedCount, 3);
    expect(downloads.get('n3380le_1')!.body, '新本文1');
    expect(downloads.get('n3380le_3')!.sourceUpdatedAt, 'new');
    expect(readMarks.get('n3380le_1')!.readAt, readAt);
    expect(work.summary, '元の説明文');
  });

  test('旧データは保留、一致版は更新不要、新着話は取得しない', () async {
    final legacy = downloads.get('n3380le_2')!;
    legacy.sourceId = '';
    await legacy.save();

    client.entries = [entry(1), entry(2), entry(3, stamp: 'old'), entry(4)];

    final result = await repository.refreshDownloadedWork(work: work);

    expect(client.bodyCalls, [1]);
    expect(result.updatedCount, 1);
    expect(result.skippedCount, 1);
    expect(result.titleUpdatedCount, 1);
    expect(downloads.containsKey('n3380le_4'), isFalse);
  });

  test('1話の取得失敗後も後続を更新し、失敗した話は維持する', () async {
    client.failNumbers.add(2);

    final result = await repository.refreshDownloadedWork(work: work);

    expect(client.bodyCalls, [1, 2, 3]);
    expect(result.updatedCount, 2);
    expect(result.failedCount, 1);
    expect(downloads.get('n3380le_2')!.body, '旧本文2');
    expect(downloads.get('n3380le_2')!.sourceUpdatedAt, 'old');
    expect(downloads.get('n3380le_3')!.body, '新本文3');
  });

  test('目次取得失敗では本文を取得せず、失敗後は再実行できる', () async {
    client.failList = true;

    await expectLater(
      repository.refreshDownloadedWork(work: work),
      throwsStateError,
    );
    expect(client.bodyCalls, isEmpty);
    expect(downloads.get('n3380le_1')!.body, '旧本文1');

    client.failList = false;
    final result = await repository.refreshDownloadedWork(work: work);
    expect(result.updatedCount, 3);
  });

  test('重複目次では最初の本文取得前に停止する', () async {
    client.entries = [entry(1), entry(1)];

    await expectLater(
      repository.refreshDownloadedWork(work: work),
      throwsFormatException,
    );
    expect(client.bodyCalls, isEmpty);
    expect(downloads.get('n3380le_1')!.body, '旧本文1');
  });

  test('順番待ち中に変更された本文を古い計画で更新しない', () async {
    client.onBodyFetch = (number) async {
      if (number == 1) {
        final second = downloads.get('n3380le_2')!;
        second.body = '別処理の本文';
        await second.save();
      }
    };

    final result = await repository.refreshDownloadedWork(work: work);

    expect(client.bodyCalls, [1, 3]);
    expect(result.updatedCount, 2);
    expect(result.skippedCount, 1);
    expect(downloads.get('n3380le_2')!.body, '別処理の本文');
  });

  test('開始前キャンセルでは目次も本文も取得しない', () async {
    final cancellation = DownloadRefreshCancellation()..cancel();

    final result = await repository.refreshDownloadedWork(
      work: work,
      cancellation: cancellation,
    );

    expect(client.listCalls, 0);
    expect(client.bodyCalls, isEmpty);
    expect(result.canceledCount, 3);
  });

  test('目次取得中から同じ作品の重複実行を拒否する', () async {
    client.onList = () async {
      await expectLater(
        repository.refreshDownloadedWork(work: work),
        throwsStateError,
      );
    };

    final result = await repository.refreshDownloadedWork(work: work);

    expect(client.listCalls, 1);
    expect(result.updatedCount, 3);
  });

  test('強制再取得は既知の同じ版にも適用する', () async {
    client.entries = [
      entry(1, stamp: 'old'),
      entry(2, stamp: 'old'),
      entry(3, stamp: 'old'),
    ];

    final normal = await repository.refreshDownloadedWork(work: work);
    expect(normal.titleUpdatedCount, 3);
    expect(client.bodyCalls, isEmpty);

    final forced = await repository.refreshDownloadedWork(
      work: work,
      forceRefresh: true,
    );
    expect(forced.updatedCount, 3);
    expect(client.bodyCalls, [1, 2, 3]);
  });
}

class _TestClient extends NarouApiClient {
  List<Map<String, String>> entries = [];
  int listCalls = 0;
  bool failList = false;
  final bodyCalls = <int>[];
  final failNumbers = <int>{};
  Future<void> Function()? onList;
  Future<void> Function(int)? onBodyFetch;

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(String ncode) async {
    listCalls++;
    if (failList) {
      throw StateError('test list failure');
    }
    await onList?.call();
    return entries.map((entry) => Map<String, String>.from(entry)).toList();
  }

  @override
  Future<Episode> fetchEpisodeBodyForRefresh({
    required String workId,
    required int episodeNo,
    required String episodeTitle,
    required String sourceId,
  }) async {
    bodyCalls.add(episodeNo);
    if (failNumbers.contains(episodeNo)) {
      throw StateError('test body failure');
    }
    await onBodyFetch?.call(episodeNo);
    return Episode(
      workId: workId,
      episodeNo: episodeNo,
      episodeTitle: episodeTitle,
      body: '新本文$episodeNo',
      fetchedAt: DateTime.now(),
    );
  }
}

class _TestIllustrations extends IllustrationStorageService {
  @override
  Future<String> prepareRefreshedBody({
    required String siteKey,
    required String workId,
    required int episodeNo,
    required String body,
  }) async => body;
}
