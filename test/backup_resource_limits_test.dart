import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/backup_service.dart';

void main() {
  group('BackupService 容量制限', () {
    test('通常のバックアップを受け入れる', () {
      final bytes = buildBackup();

      expect(
        () => BackupService.validateBackupForTesting(bytes),
        returnsNormally,
      );
    });

    test('ZIP本体の容量超過を拒否する', () {
      final bytes = buildBackup();

      expect(
        () => BackupService.validateBackupForTesting(
          bytes,
          maximumArchiveBytes: bytes.length - 1,
        ),
        throwsFormatException,
      );
    });

    test('エントリ数超過を拒否する', () {
      final bytes = buildBackup();

      expect(
        () => BackupService.validateBackupForTesting(bytes, maximumEntries: 8),
        throwsFormatException,
      );
    });

    test('展開後の合計容量超過を拒否する', () {
      final bytes = buildBackup();

      expect(
        () => BackupService.validateBackupForTesting(
          bytes,
          maximumExpandedBytes: 8,
        ),
        throwsFormatException,
      );
    });

    test('manifestの容量超過を拒否する', () {
      final bytes = buildBackup();

      expect(
        () => BackupService.validateBackupForTesting(
          bytes,
          maximumManifestBytes: 1,
        ),
        throwsFormatException,
      );
    });

    test('Hiveファイルの容量超過を拒否する', () {
      final bytes = buildBackup();

      expect(
        () => BackupService.validateBackupForTesting(
          bytes,
          maximumHiveFileBytes: 0,
        ),
        throwsFormatException,
      );
    });

    test('挿絵1ファイルの容量超過を拒否する', () {
      final bytes = buildBackup(includeIllustration: true);

      expect(
        () => BackupService.validateBackupForTesting(
          bytes,
          maximumIllustrationBytes: 0,
        ),
        throwsFormatException,
      );
    });
  });
}

Uint8List buildBackup({bool includeIllustration = false}) {
  const boxNames = <String>[
    'works',
    'episodes',
    'favorites',
    'saved_searches',
    'history',
    'download_jobs',
    'downloads',
    'read_marks',
  ];

  final archive = Archive();

  final manifestBytes = utf8.encode(
    jsonEncode(<String, dynamic>{
      'format': 'read_book_hive_backup',
      'formatVersion': 1,
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'boxes': boxNames,
    }),
  );

  archive.addFile(
    ArchiveFile(
      'manifest.json',
      manifestBytes.length,
      Uint8List.fromList(manifestBytes),
    ),
  );

  for (final boxName in boxNames) {
    archive.addFile(
      ArchiveFile('hive/$boxName.hive', 1, Uint8List.fromList(<int>[0])),
    );
  }

  if (includeIllustration) {
    archive.addFile(
      ArchiveFile(
        'illustrations/narou/n3380le/1/image.jpg',
        1,
        Uint8List.fromList(<int>[1]),
      ),
    );
  }

  final encoded = ZipEncoder().encode(archive);

  if (encoded == null) {
    throw StateError('テスト用ZIPを作成できませんでした。');
  }

  return Uint8List.fromList(encoded);
}
