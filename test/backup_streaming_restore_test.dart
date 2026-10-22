import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/backup_service.dart';

void main() {
  group('BackupService ファイルベース復元', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'read_book_streaming_restore_test_',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('Hiveと挿絵をステージング領域へ展開する', () async {
      final backupFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}backup.zip',
      );

      final stagingDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}staging',
      );

      final zipBytes = _buildBackup(illustrationBytes: const <int>[1, 2, 3, 4]);

      await backupFile.writeAsBytes(zipBytes, flush: true);

      await BackupService.extractBackupFileForTesting(
        backupFile.path,
        stagingDirectory.path,
      );

      for (final boxName in _boxNames) {
        final hiveFile = File(
          '${stagingDirectory.path}'
          '${Platform.pathSeparator}'
          'hive'
          '${Platform.pathSeparator}'
          '$boxName.hive',
        );

        expect(await hiveFile.exists(), isTrue);
        expect(await hiveFile.readAsBytes(), orderedEquals(<int>[0]));
      }

      final illustrationFile = File(
        '${stagingDirectory.path}'
        '${Platform.pathSeparator}'
        'illustrations'
        '${Platform.pathSeparator}'
        'narou'
        '${Platform.pathSeparator}'
        'n3380le'
        '${Platform.pathSeparator}'
        '1'
        '${Platform.pathSeparator}'
        'image.jpg',
      );

      expect(await illustrationFile.exists(), isTrue);
      expect(
        await illustrationFile.readAsBytes(),
        orderedEquals(<int>[1, 2, 3, 4]),
      );
    });

    test('不正な挿絵パスではステージング領域を残さない', () async {
      final backupFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}invalid.zip',
      );

      final stagingDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}invalid_staging',
      );

      final zipBytes = _buildBackup(
        illustrationName: 'illustrations/narou/../outside.jpg',
      );

      await backupFile.writeAsBytes(zipBytes, flush: true);

      await expectLater(
        BackupService.extractBackupFileForTesting(
          backupFile.path,
          stagingDirectory.path,
        ),
        throwsFormatException,
      );

      expect(await stagingDirectory.exists(), isFalse);
    });
  });
}

const _boxNames = <String>[
  'works',
  'episodes',
  'favorites',
  'saved_searches',
  'history',
  'download_jobs',
  'downloads',
  'read_marks',
];

Uint8List _buildBackup({
  String illustrationName = 'illustrations/narou/n3380le/1/image.jpg',
  List<int> illustrationBytes = const <int>[1],
}) {
  final archive = Archive();

  final manifestBytes = utf8.encode(
    jsonEncode(<String, dynamic>{
      'format': 'read_book_hive_backup',
      'formatVersion': 1,
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'boxes': _boxNames,
    }),
  );

  archive.addFile(
    ArchiveFile(
      'manifest.json',
      manifestBytes.length,
      Uint8List.fromList(manifestBytes),
    ),
  );

  for (final boxName in _boxNames) {
    archive.addFile(
      ArchiveFile('hive/$boxName.hive', 1, Uint8List.fromList(<int>[0])),
    );
  }

  archive.addFile(
    ArchiveFile(
      illustrationName,
      illustrationBytes.length,
      Uint8List.fromList(illustrationBytes),
    ),
  );

  final encoded = ZipEncoder().encode(archive);

  if (encoded == null) {
    throw StateError('テスト用ZIPを作成できませんでした。');
  }

  return Uint8List.fromList(encoded);
}
