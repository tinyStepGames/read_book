import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/services/illustration_storage_service.dart';
import 'package:read_book/services/novel_repository.dart';

void main() {
  late Directory temporaryDirectory;
  late _RecordingIllustrationStorageService illustrationStorageService;
  late NovelRepository repository;
  late Box<Download> downloadBox;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_repository_deletion_test_',
    );

    Hive.init(temporaryDirectory.path);

    final adapter = DownloadAdapter();

    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }

    downloadBox = await Hive.openBox<Download>('downloads');
    illustrationStorageService = _RecordingIllustrationStorageService();
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

  Download createDownload(String workId, int episodeNo) {
    return Download(
      workId: workId,
      episodeNo: episodeNo,
      episodeTitle: '第$episodeNo話',
      body: '本文',
      downloadedAt: DateTime(2026),
      publishedAt: '',
    );
  }

  test('作品単位の削除で本文と挿絵を削除する', () async {
    await downloadBox.put('target_1', createDownload('n3380le', 1));
    await downloadBox.put('target_2', createDownload('n3380le', 2));
    await downloadBox.put('other_1', createDownload('other', 1));

    await repository.deleteAllDownloads('n3380le', site: Site.narou);

    expect(downloadBox.get('target_1'), isNull);
    expect(downloadBox.get('target_2'), isNull);
    expect(downloadBox.get('other_1'), isNotNull);
    expect(illustrationStorageService.deletedWorks, <String>['narou/n3380le']);
  });

  test('1話単位の削除で対象話の本文と挿絵だけを削除する', () async {
    await downloadBox.put('target_1', createDownload('n3380le', 1));
    await downloadBox.put('target_2', createDownload('n3380le', 2));
    await downloadBox.put('other_1', createDownload('other', 1));

    await repository.deleteDownloadedEpisode(
      workId: 'n3380le',
      episodeNo: 1,
      site: Site.narou,
    );

    expect(downloadBox.get('target_1'), isNull);
    expect(downloadBox.get('target_2'), isNotNull);
    expect(downloadBox.get('other_1'), isNotNull);
    expect(illustrationStorageService.deletedEpisodes, <String>[
      'narou/n3380le/1',
    ]);
  });
}

class _RecordingIllustrationStorageService extends IllustrationStorageService {
  final List<String> deletedWorks = <String>[];
  final List<String> deletedEpisodes = <String>[];

  @override
  Future<void> deleteWork({
    required String siteKey,
    required String workId,
  }) async {
    deletedWorks.add('$siteKey/$workId');
  }

  @override
  Future<void> deleteEpisode({
    required String siteKey,
    required String workId,
    required int episodeNo,
  }) async {
    deletedEpisodes.add('$siteKey/$workId/$episodeNo');
  }
}
