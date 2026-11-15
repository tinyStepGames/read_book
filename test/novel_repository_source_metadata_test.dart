import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/episode.dart';
import 'package:read_book/models/read_mark.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  late Directory temporaryDirectory;
  late Box<Download> downloads;
  late Box<Episode> episodes;
  late Box<ReadMark> readMarks;
  late _TestIllustrationStorageService illustrations;
  late NovelRepository repository;

  const workId = 'n3380le';
  const key = '${workId}_1';
  const sourceId = 'https://ncode.syosetu.com/n3380le/1/';
  const oldStamp = '2026-11-14T03:00:00.000Z';
  const newStamp = '2026-11-15T03:00:00.000Z';

  Work createWork() {
    return Work(
      workId: workId,
      siteIndex: Site.narou.index,
      title: 'テスト作品',
      author: 'テスト作者',
      genre: '',
      summary: '',
      totalEpisodeCount: 1,
      checkedEpisodeCount: 1,
      lastUpdatedAt: DateTime(2026),
      isCompleted: false,
      authorId: '',
      keyword: '',
    );
  }

  Future<void> putExisting() async {
    await downloads.put(
      key,
      Download(
        workId: workId,
        episodeNo: 1,
        episodeTitle: '保存済みタイトル',
        body: '保存済み本文',
        downloadedAt: DateTime(2026),
        sourceId: sourceId,
        sourceUpdatedAt: oldStamp,
      ),
    );
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_source_metadata_test_',
    );
    Hive.init(temporaryDirectory.path);

    final downloadAdapter = DownloadAdapter();
    if (!Hive.isAdapterRegistered(downloadAdapter.typeId)) {
      Hive.registerAdapter(downloadAdapter);
    }

    final episodeAdapter = EpisodeAdapter();
    if (!Hive.isAdapterRegistered(episodeAdapter.typeId)) {
      Hive.registerAdapter(episodeAdapter);
    }

    final workAdapter = WorkAdapter();
    if (!Hive.isAdapterRegistered(workAdapter.typeId)) {
      Hive.registerAdapter(workAdapter);
    }

    final readMarkAdapter = ReadMarkAdapter();
    if (!Hive.isAdapterRegistered(readMarkAdapter.typeId)) {
      Hive.registerAdapter(readMarkAdapter);
    }

    await Hive.openBox<Work>('works');
    downloads = await Hive.openBox<Download>('downloads');
    episodes = await Hive.openBox<Episode>('episodes');
    readMarks = await Hive.openBox<ReadMark>('read_marks');

    illustrations = _TestIllustrationStorageService();
    repository = NovelRepository(illustrationStorageService: illustrations);
  });

  tearDown(() async {
    await Hive.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('新規本文と同期情報を保存し、Boxを開き直しても保持する', () async {
    await repository.saveDownloadedEpisodeBody(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
      body: '新規本文',
      sourceId: ' $sourceId ',
      sourceUpdatedAt: ' $newStamp ',
    );

    expect(readMarks.length, 0);

    await downloads.close();
    downloads = await Hive.openBox<Download>('downloads');

    final saved = downloads.get(key)!;
    expect(saved.body, '新規本文');
    expect(saved.sourceId, sourceId);
    expect(saved.sourceUpdatedAt, newStamp);
  });

  test('同期情報のない旧形式の呼び出しも保存できる', () async {
    await repository.saveDownloadedEpisodeBody(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
      body: '新規本文',
    );

    final saved = downloads.get(key)!;
    expect(saved.sourceId, isEmpty);
    expect(saved.sourceUpdatedAt, isEmpty);
  });

  test('識別子なしの更新日時だけでは同期済みと記録しない', () async {
    await repository.saveDownloadedEpisodeBody(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
      body: '新規本文',
      sourceUpdatedAt: newStamp,
    );

    expect(downloads.get(key)!.sourceUpdatedAt, isEmpty);
  });

  test('既存本文と同じ内容の保存では同期情報を最新化しない', () async {
    await putExisting();

    await repository.saveDownloadedEpisodeBody(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '新しいタイトル',
      body: '保存済み本文',
      sourceId: sourceId,
      sourceUpdatedAt: newStamp,
    );

    final saved = downloads.get(key)!;
    expect(saved.body, '保存済み本文');
    expect(saved.episodeTitle, '保存済みタイトル');
    expect(saved.sourceId, sourceId);
    expect(saved.sourceUpdatedAt, oldStamp);
    expect(readMarks.length, 0);
  });

  test('既存本文が変わった場合は古い同期情報を無効化する', () async {
    await putExisting();

    await repository.saveDownloadedEpisodeBody(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
      body: '別の本文',
      sourceId: sourceId,
      sourceUpdatedAt: newStamp,
    );

    final saved = downloads.get(key)!;
    expect(saved.body, '別の本文');
    expect(saved.sourceId, isEmpty);
    expect(saved.sourceUpdatedAt, isEmpty);
    expect(readMarks.length, 0);
  });

  test('キャッシュ本文には現在の目次の同期情報を付与しない', () async {
    await episodes.put(
      key,
      Episode(
        workId: workId,
        episodeNo: 1,
        episodeTitle: 'キャッシュのタイトル',
        body: 'キャッシュ本文',
        fetchedAt: DateTime(2026),
      ),
    );

    await repository.downloadEpisode(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
      sourceId: sourceId,
      sourceUpdatedAt: newStamp,
    );

    final saved = downloads.get(key)!;
    expect(saved.body, 'キャッシュ本文');
    expect(saved.sourceId, isEmpty);
    expect(saved.sourceUpdatedAt, isEmpty);
    expect(readMarks.length, 0);
  });

  test('通常ダウンロードで既存本文の同期情報だけを更新しない', () async {
    await putExisting();

    await repository.downloadEpisode(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
      sourceId: sourceId,
      sourceUpdatedAt: newStamp,
    );

    final saved = downloads.get(key)!;
    expect(saved.body, '保存済み本文');
    expect(saved.sourceUpdatedAt, oldStamp);
    expect(readMarks.length, 0);
  });

  test('挿絵保存に失敗した場合は本文も同期情報も新規保存しない', () async {
    illustrations.fail = true;

    await expectLater(
      repository.saveDownloadedEpisodeBody(
        work: createWork(),
        episodeNo: 1,
        episodeTitle: '第1話',
        body: '新規本文',
        sourceId: sourceId,
        sourceUpdatedAt: newStamp,
      ),
      throwsStateError,
    );

    expect(downloads.containsKey(key), isFalse);
    expect(readMarks.length, 0);
  });
}

class _TestIllustrationStorageService extends IllustrationStorageService {
  bool fail = false;

  @override
  Future<String> localizeDownloadedBody({
    required String siteKey,
    required String workId,
    required int episodeNo,
    required String body,
  }) async {
    if (fail) {
      throw StateError('test storage failure');
    }
    return body;
  }
}
