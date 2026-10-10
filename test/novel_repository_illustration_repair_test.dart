import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/read_mark.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  late Directory temporaryDirectory;
  late Box<Download> downloadBox;
  late _RepairIllustrationStorageService illustrationStorageService;
  late NovelRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_repository_repair_test_',
    );

    Hive.init(temporaryDirectory.path);

    final downloadAdapter = DownloadAdapter();
    if (!Hive.isAdapterRegistered(downloadAdapter.typeId)) {
      Hive.registerAdapter(downloadAdapter);
    }

    final readMarkAdapter = ReadMarkAdapter();
    if (!Hive.isAdapterRegistered(readMarkAdapter.typeId)) {
      Hive.registerAdapter(readMarkAdapter);
    }

    downloadBox = await Hive.openBox<Download>('downloads');
    await Hive.openBox<ReadMark>('read_marks');

    illustrationStorageService = _RepairIllustrationStorageService();
    repository = NovelRepository(
      illustrationStorageService: illustrationStorageService,
    );
  });

  tearDown(() async {
    await Hive.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('Readerで開いたときに修復済み本文を保存して返す', () async {
    const originalBody =
        '@@READ_BOOK_RICH_V1@@\n'
        '<img src="https://img1.mitemin.net/example/image.jpg" '
        'alt="挿絵">';

    const repairedBody =
        '@@READ_BOOK_RICH_V1@@\n'
        '<img src="https://img1.mitemin.net/example/image.jpg" '
        'data-local-src="narou/n3380le/1/image.jpg" '
        'alt="挿絵">';

    await downloadBox.put('n3380le_1', createDownload(originalBody));

    illustrationStorageService.resultBody = repairedBody;

    final body = await repository.fetchEpisode(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
    );

    expect(body, repairedBody);
    expect(downloadBox.get('n3380le_1')?.body, repairedBody);
    expect(illustrationStorageService.callCount, 1);
    expect(illustrationStorageService.lastSiteKey, 'narou');
    expect(illustrationStorageService.lastWorkId, 'n3380le');
    expect(illustrationStorageService.lastEpisodeNo, 1);
  });

  test('挿絵修復に失敗しても保存済み本文を返す', () async {
    const originalBody =
        '@@READ_BOOK_RICH_V1@@\n'
        '<img src="https://img1.mitemin.net/example/image.jpg" '
        'alt="挿絵">';

    await downloadBox.put('n3380le_1', createDownload(originalBody));

    illustrationStorageService.error = StateError('offline');

    final body = await repository.fetchEpisode(
      work: createWork(),
      episodeNo: 1,
      episodeTitle: '第1話',
    );

    expect(body, originalBody);
    expect(downloadBox.get('n3380le_1')?.body, originalBody);
    expect(illustrationStorageService.callCount, 1);
  });
}

Download createDownload(String body) {
  return Download(
    workId: 'n3380le',
    episodeNo: 1,
    episodeTitle: '第1話',
    body: body,
    downloadedAt: DateTime(2026),
    publishedAt: '',
  );
}

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

class _RepairIllustrationStorageService extends IllustrationStorageService {
  String? resultBody;
  Object? error;
  int callCount = 0;
  String? lastSiteKey;
  String? lastWorkId;
  int? lastEpisodeNo;

  @override
  Future<String> localizeDownloadedBody({
    required String siteKey,
    required String workId,
    required int episodeNo,
    required String body,
  }) async {
    callCount++;
    lastSiteKey = siteKey;
    lastWorkId = workId;
    lastEpisodeNo = episodeNo;

    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }

    return resultBody ?? body;
  }
}
