import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/episode.dart';
import 'package:read_book/models/read_mark.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/services/narou_api_client.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  late Directory directory;
  late Box<Download> downloads;
  late Box<ReadMark> readMarks;
  late Work work;
  late NovelRepository repository;
  late _TestNarouClient client;
  late _TestIllustrations illustrations;

  const key = 'n3380le_1';
  const sourceId = 'https://ncode.syosetu.com/n3380le/1/';

  Map<String, String> entry() => {
    'episodeNo': '1',
    'title': '新タイトル',
    'publishedAt': '2026/11/01 12:00',
    'sourceId': sourceId,
    'sourceUpdatedAt': 'new-version',
  };

  Future<bool> refresh() =>
      repository.refreshDownloadedEpisode(work: work, episodeEntry: entry());

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'read_book_episode_refresh_test_',
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
      summary: '',
      totalEpisodeCount: 1,
      checkedEpisodeCount: 1,
      lastUpdatedAt: DateTime(2026),
      isCompleted: false,
      authorId: '',
      keyword: '',
    );
    await works.put(work.workId, work);
    await downloads.put(
      key,
      Download(
        workId: work.workId,
        episodeNo: 1,
        episodeTitle: '旧タイトル',
        body: '旧本文',
        downloadedAt: DateTime(2026),
        sourceId: sourceId,
        sourceUpdatedAt: 'old-version',
      ),
    );
    await readMarks.put(
      key,
      ReadMark(workId: work.workId, episodeNo: 1, readAt: DateTime(2026)),
    );

    client = _TestNarouClient();
    illustrations = _TestIllustrations();
    repository = NovelRepository(
      narouApiClient: client,
      illustrationStorageService: illustrations,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('本文・タイトル・同期情報を差し替え、旧オブジェクトと既読は変えない', () async {
    final original = downloads.get(key)!;
    final readAt = readMarks.get(key)!.readAt;

    expect(await refresh(), isTrue);

    final updated = downloads.get(key)!;
    expect(updated.body, '新本文');
    expect(updated.episodeTitle, '新タイトル');
    expect(updated.sourceUpdatedAt, 'new-version');
    expect(updated.publishedAt, '2026/11/01 12:00');
    expect(original.body, '旧本文');
    expect(original.sourceUpdatedAt, 'old-version');
    expect(readMarks.get(key)!.readAt, readAt);
    expect(client.calls, 1);
    expect(illustrations.calls, 1);

    await downloads.close();
    downloads = await Hive.openBox<Download>('downloads');
    expect(downloads.get(key)!.body, '新本文');
  });

  test('取得失敗では旧本文・同期情報を維持する', () async {
    client.fail = true;
    await expectLater(refresh(), throwsStateError);
    expect(downloads.get(key)!.body, '旧本文');
    expect(downloads.get(key)!.sourceUpdatedAt, 'old-version');
    expect(illustrations.calls, 0);
  });

  test('空本文では保存しない', () async {
    client.body = '   ';
    await expectLater(refresh(), throwsStateError);
    expect(downloads.get(key)!.body, '旧本文');
  });

  test('挿絵準備失敗では旧本文を維持する', () async {
    illustrations.fail = true;
    await expectLater(refresh(), throwsStateError);
    expect(downloads.get(key)!.body, '旧本文');
    expect(downloads.get(key)!.sourceUpdatedAt, 'old-version');
  });

  test('識別子が一致しなければ取得しない', () async {
    final changed = entry()..['sourceId'] = 'different';
    expect(
      await repository.refreshDownloadedEpisode(
        work: work,
        episodeEntry: changed,
      ),
      isFalse,
    );
    expect(client.calls, 0);
  });

  test('取得中に削除された本文を復活させない', () async {
    client.onFetch = () async => downloads.delete(key);
    expect(await refresh(), isFalse);
    expect(downloads.containsKey(key), isFalse);
    expect(illustrations.calls, 0);
  });

  test('挿絵準備中に変更された本文を上書きしない', () async {
    illustrations.onPrepare = () async {
      final current = downloads.get(key)!;
      current.body = '別処理が保存した本文';
      await current.save();
    };

    expect(await refresh(), isFalse);
    expect(downloads.get(key)!.body, '別処理が保存した本文');
    expect(downloads.get(key)!.sourceUpdatedAt, 'old-version');
  });

  test('同じ話の同時更新を拒否し、完了後は再実行できる', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    client.onFetch = () async {
      entered.complete();
      await release.future;
    };

    final first = refresh();
    await entered.future;

    await expectLater(refresh(), throwsStateError);

    release.complete();
    expect(await first, isTrue);

    client.onFetch = null;
    expect(await refresh(), isTrue);
  });

  test('なろう更新専用取得は作品外URLを通信前に拒否する', () async {
    await expectLater(
      NarouApiClient().fetchEpisodeBodyForRefresh(
        workId: 'n3380le',
        episodeNo: 1,
        episodeTitle: '第1話',
        sourceId: 'https://example.invalid/1/',
      ),
      throwsArgumentError,
    );
  });
}

class _TestNarouClient extends NarouApiClient {
  int calls = 0;
  bool fail = false;
  String body = '新本文';
  Future<void> Function()? onFetch;

  @override
  Future<Episode> fetchEpisodeBodyForRefresh({
    required String workId,
    required int episodeNo,
    required String episodeTitle,
    required String sourceId,
  }) async {
    calls++;
    if (fail) {
      throw StateError('test network failure');
    }
    await onFetch?.call();
    return Episode(
      workId: workId,
      episodeNo: episodeNo,
      episodeTitle: episodeTitle,
      body: body,
      fetchedAt: DateTime.now(),
    );
  }
}

class _TestIllustrations extends IllustrationStorageService {
  int calls = 0;
  bool fail = false;
  Future<void> Function()? onPrepare;

  @override
  Future<String> prepareRefreshedBody({
    required String siteKey,
    required String workId,
    required int episodeNo,
    required String body,
  }) async {
    calls++;
    if (fail) {
      throw StateError('test illustration failure');
    }
    await onPrepare?.call();
    return body;
  }
}
