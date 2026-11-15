import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/episode.dart';
import 'package:read_book/models/read_mark.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/services/kakuyomu_scraper.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  const workId = '1234567890123456789';
  const episodeId = '2345678901234567890';
  const key = '${workId}_1';

  late Directory directory;
  late Box<Work> works;
  late Box<Download> downloads;
  late Box<ReadMark> readMarks;
  late Work work;
  late Map<String, String> latest;
  late _TestKakuyomuScraper scraper;
  late _TestIllustrations illustrations;
  late NovelRepository repository;

  Future<bool> refresh() =>
      repository.refreshDownloadedEpisode(work: work, episodeEntry: latest);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'read_book_kakuyomu_refresh_test_',
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

    works = await Hive.openBox<Work>('works');
    downloads = await Hive.openBox<Download>('downloads');
    readMarks = await Hive.openBox<ReadMark>('read_marks');

    // episodesキャッシュBoxは開きません。
    // 更新経路がキャッシュへ依存しないことも確認します。
    work = Work(
      workId: workId,
      siteIndex: Site.kakuyomu.index,
      title: 'カクヨム作品',
      author: '作者',
      genre: '',
      summary: '保存済み説明文',
      totalEpisodeCount: 1,
      checkedEpisodeCount: 1,
      lastUpdatedAt: DateTime(2026),
      isCompleted: false,
      authorId: '',
      keyword: '',
    );
    await works.put(workId, work);

    await downloads.put(
      key,
      Download(
        workId: workId,
        episodeNo: 1,
        episodeTitle: '旧タイトル',
        body: '旧本文',
        downloadedAt: DateTime(2026),
        publishedAt: '旧掲載日',
        sourceId: episodeId,
        sourceUpdatedAt: 'old-version',
      ),
    );
    await readMarks.put(
      key,
      ReadMark(workId: workId, episodeNo: 1, readAt: DateTime(2026)),
    );

    latest = {
      'episodeNo': '1',
      'title': '新タイトル',
      'sourceId': episodeId,
      'sourceUpdatedAt': 'new-version',
      'publishedAt': '新掲載日',
    };

    scraper = _TestKakuyomuScraper();
    illustrations = _TestIllustrations();
    repository = NovelRepository(
      kakuyomuScraper: scraper,
      illustrationStorageService: illustrations,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('確認済みepisodeIdで取得し、本文と同期情報を保存する', () async {
    final original = downloads.get(key)!;
    final readAt = readMarks.get(key)!.readAt;

    expect(await refresh(), isTrue);

    expect(scraper.calls, 1);
    expect(scraper.resolveCalls, 0);
    expect(scraper.receivedWorkId, workId);
    expect(scraper.receivedEpisodeId, episodeId);
    expect(scraper.receivedEpisodeNo, 1);

    final updated = downloads.get(key)!;
    expect(updated.body, 'カクヨムの新本文');
    expect(updated.episodeTitle, '新タイトル');
    expect(updated.sourceId, episodeId);
    expect(updated.sourceUpdatedAt, 'new-version');
    expect(updated.publishedAt, '新掲載日');
    expect(original.body, '旧本文');
    expect(readMarks.get(key)!.readAt, readAt);
    expect(illustrations.receivedSiteKey, 'kakuyomu');

    await downloads.close();
    downloads = await Hive.openBox<Download>('downloads');
    expect(downloads.get(key)!.body, 'カクヨムの新本文');
  });

  test('識別子が異なる場合は取得も保存もしない', () async {
    latest['sourceId'] = '9999999999999999999';

    expect(await refresh(), isFalse);
    expect(scraper.calls, 0);
    expect(downloads.get(key)!.body, '旧本文');
  });

  test('識別子のない旧データを話番号だけで更新しない', () async {
    final original = downloads.get(key)!;
    original.sourceId = '';
    await original.save();

    expect(await refresh(), isFalse);
    expect(scraper.calls, 0);
    expect(downloads.get(key)!.body, '旧本文');
  });

  test('一致していても数字以外のepisodeIdは取得前に拒否する', () async {
    final original = downloads.get(key)!;
    original.sourceId = '../invalid';
    await original.save();
    latest['sourceId'] = '../invalid';

    await expectLater(refresh(), throwsArgumentError);
    expect(scraper.calls, 0);
    expect(downloads.get(key)!.body, '旧本文');
  });

  test('取得失敗では旧本文を維持し、失敗後は再実行できる', () async {
    scraper.fail = true;
    await expectLater(refresh(), throwsStateError);

    expect(downloads.get(key)!.body, '旧本文');
    expect(downloads.get(key)!.sourceUpdatedAt, 'old-version');
    expect(illustrations.calls, 0);

    scraper.fail = false;
    expect(await refresh(), isTrue);
  });

  test('空本文では保存しない', () async {
    scraper.body = '   ';

    await expectLater(refresh(), throwsStateError);
    expect(downloads.get(key)!.body, '旧本文');
    expect(illustrations.calls, 0);
  });

  test('取得結果の作品IDが異なれば保存しない', () async {
    scraper.returnedWorkId = '9999999999999999999';

    await expectLater(refresh(), throwsStateError);
    expect(downloads.get(key)!.body, '旧本文');
    expect(illustrations.calls, 0);
  });

  test('取得結果の話番号が異なれば保存しない', () async {
    scraper.returnedEpisodeNo = 2;

    await expectLater(refresh(), throwsStateError);
    expect(downloads.get(key)!.body, '旧本文');
    expect(illustrations.calls, 0);
  });

  test('挿絵準備失敗では旧本文と同期情報を維持する', () async {
    illustrations.fail = true;

    await expectLater(refresh(), throwsStateError);
    expect(downloads.get(key)!.body, '旧本文');
    expect(downloads.get(key)!.sourceUpdatedAt, 'old-version');
  });

  test('取得中に作品が削除された場合は保存しない', () async {
    scraper.onFetch = () async {
      await works.delete(workId);
    };

    expect(await refresh(), isFalse);
    expect(works.containsKey(workId), isFalse);
    expect(downloads.get(key)!.body, '旧本文');
    expect(illustrations.calls, 0);
  });

  test('挿絵準備中に別オブジェクトへ差し替わった本文を上書きしない', () async {
    illustrations.onPrepare = () async {
      await downloads.put(
        key,
        Download(
          workId: workId,
          episodeNo: 1,
          episodeTitle: '別処理のタイトル',
          body: '別処理の本文',
          downloadedAt: DateTime(2026, 11),
          sourceId: episodeId,
          sourceUpdatedAt: 'another-version',
        ),
      );
    };

    expect(await refresh(), isFalse);
    expect(downloads.get(key)!.body, '別処理の本文');
    expect(downloads.get(key)!.sourceUpdatedAt, 'another-version');
  });

  test('開始後に呼び出し元の目次Mapが変わっても取得時の値を使う', () async {
    scraper.onFetch = () async {
      latest['title'] = '途中で変えたタイトル';
      latest['sourceId'] = '9999999999999999999';
      latest['sourceUpdatedAt'] = '途中で変えた改稿情報';
    };

    expect(await refresh(), isTrue);
    expect(scraper.receivedEpisodeId, episodeId);

    final updated = downloads.get(key)!;
    expect(updated.episodeTitle, '新タイトル');
    expect(updated.sourceId, episodeId);
    expect(updated.sourceUpdatedAt, 'new-version');
  });
}

class _TestKakuyomuScraper extends KakuyomuScraper {
  int calls = 0;
  int resolveCalls = 0;
  bool fail = false;
  String body = 'カクヨムの新本文';
  String? returnedWorkId;
  int? returnedEpisodeNo;
  String? receivedWorkId;
  String? receivedEpisodeId;
  int? receivedEpisodeNo;
  Future<void> Function()? onFetch;

  @override
  Future<String> resolveEpisodeId({
    required String workId,
    required int episodeNo,
  }) async {
    resolveCalls++;
    throw StateError('更新処理からIDを再解決してはいけません。');
  }

  @override
  Future<Episode> fetchEpisodeBody({
    required String workId,
    required String episodeId,
    required int episodeNo,
    required String episodeTitle,
  }) async {
    calls++;
    receivedWorkId = workId;
    receivedEpisodeId = episodeId;
    receivedEpisodeNo = episodeNo;

    if (fail) {
      throw StateError('test network failure');
    }

    await onFetch?.call();

    return Episode(
      workId: returnedWorkId ?? workId,
      episodeNo: returnedEpisodeNo ?? episodeNo,
      episodeTitle: episodeTitle,
      body: body,
      fetchedAt: DateTime.now(),
    );
  }
}

class _TestIllustrations extends IllustrationStorageService {
  int calls = 0;
  bool fail = false;
  String? receivedSiteKey;
  Future<void> Function()? onPrepare;

  @override
  Future<String> prepareRefreshedBody({
    required String siteKey,
    required String workId,
    required int episodeNo,
    required String body,
  }) async {
    calls++;
    receivedSiteKey = siteKey;

    if (fail) {
      throw StateError('test illustration failure');
    }

    await onPrepare?.call();
    return body;
  }
}
