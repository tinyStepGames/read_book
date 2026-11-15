import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/download_manager.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  const sourceId = 'https://ncode.syosetu.com/n3380le/1/';
  const stamp = '2026-11-15T03:00:00.000Z';

  Work createWork() {
    return Work(
      workId: 'n3380le',
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

  test('Repositoryの一括ダウンロードで同期情報を渡す', () async {
    final repository = _RecordingRepository();

    await repository.bulkDownload(
      work: createWork(),
      episodeList: [
        {
          'episodeNo': '1',
          'title': '第1話',
          'publishedAt': '2026/11/01 12:00',
          'sourceId': sourceId,
          'sourceUpdatedAt': stamp,
        },
      ],
    );

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single['sourceId'], sourceId);
    expect(repository.calls.single['sourceUpdatedAt'], stamp);
    expect(repository.calls.single['publishedAt'], '2026/11/01 12:00');
  });

  test('古い形式の目次では空の同期情報を渡す', () async {
    final repository = _RecordingRepository();

    await repository.bulkDownload(
      work: createWork(),
      episodeList: [
        {'episodeNo': '1', 'title': '第1話'},
      ],
    );

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single['sourceId'], isEmpty);
    expect(repository.calls.single['sourceUpdatedAt'], isEmpty);
  });

  test('ダウンロード済みの話は通常の一括処理で再取得しない', () async {
    final repository = _RecordingRepository()..alreadyDownloaded = true;

    await repository.bulkDownload(
      work: createWork(),
      episodeList: [
        {
          'episodeNo': '1',
          'title': '第1話',
          'sourceId': sourceId,
          'sourceUpdatedAt': stamp,
        },
      ],
    );

    expect(repository.calls, isEmpty);
  });

  test('単話の受け口で同期情報を渡し、省略時も互換性を保つ', () async {
    final repository = _RecordingRepository();
    final manager = DownloadManager.init(repository);

    await manager.downloadSingle(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
      sourceId: sourceId,
      sourceUpdatedAt: stamp,
    );

    await manager.downloadSingle(
      work: createWork(),
      episodeNo: 2,
      episodeTitle: '第2話',
    );

    expect(repository.calls, hasLength(2));
    expect(repository.calls.first['sourceId'], sourceId);
    expect(repository.calls.first['sourceUpdatedAt'], stamp);
    expect(repository.calls.last['sourceId'], isEmpty);
    expect(repository.calls.last['sourceUpdatedAt'], isEmpty);
  }, skip: Platform.isIOS);
}

class _RecordingRepository extends NovelRepository {
  final calls = <Map<String, String>>[];
  bool alreadyDownloaded = false;

  @override
  bool isDownloaded(Work work, int episodeNo) => alreadyDownloaded;

  @override
  Future<void> updateDownloadPublishedDates({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {}

  @override
  Future<void> updateDownloadPublishedDate({
    required Work work,
    required int episodeNo,
    required String publishedAt,
  }) async {}

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
      'episodeNo': episodeNo.toString(),
      'title': episodeTitle,
      'publishedAt': publishedAt,
      'sourceId': sourceId,
      'sourceUpdatedAt': sourceUpdatedAt,
    });
  }
}
