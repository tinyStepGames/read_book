import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';

void main() {
  late Directory temporaryDirectory;
  late Box<Download> downloadBox;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_download_sync_metadata_test_',
    );

    Hive.init(temporaryDirectory.path);

    final adapter = DownloadAdapter();

    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }

    downloadBox = await Hive.openBox<Download>('download_sync_metadata');
  });

  tearDownAll(() async {
    await Hive.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('同期情報を指定しないダウンロードは空文字を使用する', () {
    final download = Download(
      workId: 'work',
      episodeNo: 1,
      episodeTitle: '第1話',
      body: '本文',
      downloadedAt: DateTime(2026),
    );

    expect(download.sourceId, isEmpty);
    expect(download.sourceUpdatedAt, isEmpty);
  });

  test('サイト側の話IDと更新情報を保存して復元できる', () async {
    final download = Download(
      workId: 'work',
      episodeNo: 1,
      episodeTitle: '更新後の第1話',
      body: '更新後の本文',
      downloadedAt: DateTime(2026, 11, 2),
      publishedAt: '2026-10-01 12:00',
      sourceId: 'episode-123',
      sourceUpdatedAt: '2026-11-02 15:30',
    );

    await downloadBox.put('work_1', download);
    await downloadBox.flush();

    final restored = downloadBox.get('work_1');

    expect(restored, isNotNull);
    expect(restored!.sourceId, 'episode-123');
    expect(restored.sourceUpdatedAt, '2026-11-02 15:30');
    expect(restored.episodeTitle, '更新後の第1話');
    expect(restored.body, '更新後の本文');
  });
}
