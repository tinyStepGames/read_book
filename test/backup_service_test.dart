import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/backup_service.dart';

void main() {
  group('BackupService 挿絵ZIP検証', () {
    test('安全な挿絵エントリを読み込む', () {
      final zipBytes = buildBackup(
        illustrationEntries: <ArchiveFile>[
          archiveFile('illustrations/narou/n3380le/1/image.jpg', <int>[
            1,
            2,
            3,
            4,
          ]),
        ],
      );

      final illustrations = BackupService.readIllustrationsForTesting(zipBytes);

      expect(illustrations.keys, <String>['narou/n3380le/1/image.jpg']);
      expect(
        illustrations['narou/n3380le/1/image.jpg'],
        orderedEquals(<int>[1, 2, 3, 4]),
      );
    });

    test('挿絵を含まない旧バックアップを受け入れる', () {
      final zipBytes = buildBackup();

      final illustrations = BackupService.readIllustrationsForTesting(zipBytes);

      expect(illustrations, isEmpty);
    });

    test('親ディレクトリへ移動するパスを拒否する', () {
      final zipBytes = buildBackup(
        illustrationEntries: <ArchiveFile>[
          archiveFile('illustrations/narou/n3380le/../outside.jpg', <int>[1]),
        ],
      );

      expect(
        () => BackupService.readIllustrationsForTesting(zipBytes),
        throwsFormatException,
      );
    });

    test('バックスラッシュは安全な区切りへ正規化される', () {
      final zipBytes = buildBackup(
        illustrationEntries: <ArchiveFile>[
          archiveFile(r'illustrations\narou\n3380le\1\image.jpg', <int>[1]),
        ],
      );

      final illustrations = BackupService.readIllustrationsForTesting(zipBytes);

      expect(illustrations.keys, <String>['narou/n3380le/1/image.jpg']);
      expect(
        illustrations['narou/n3380le/1/image.jpg'],
        orderedEquals(<int>[1]),
      );
    });

    test('バックスラッシュによる親ディレクトリ移動を拒否する', () {
      final zipBytes = buildBackup(
        illustrationEntries: <ArchiveFile>[
          archiveFile(r'illustrations\narou\n3380le\..\outside.jpg', <int>[1]),
        ],
      );

      expect(
        () => BackupService.readIllustrationsForTesting(zipBytes),
        throwsFormatException,
      );
    });

    test('ドライブ区切りを含むパスを拒否する', () {
      final zipBytes = buildBackup(
        illustrationEntries: <ArchiveFile>[
          archiveFile('illustrations/C:/outside.jpg', <int>[1]),
        ],
      );

      expect(
        () => BackupService.readIllustrationsForTesting(zipBytes),
        throwsFormatException,
      );
    });

    test('同じ挿絵パスはZIPデコーダーが最後の内容へ統合する', () {
      final zipBytes = buildBackup(
        illustrationEntries: <ArchiveFile>[
          archiveFile('illustrations/narou/n3380le/1/image.jpg', <int>[1]),
          archiveFile('illustrations/narou/n3380le/1/image.jpg', <int>[2]),
        ],
      );

      final illustrations = BackupService.readIllustrationsForTesting(zipBytes);

      expect(illustrations.keys, <String>['narou/n3380le/1/image.jpg']);
      expect(
        illustrations['narou/n3380le/1/image.jpg'],
        orderedEquals(<int>[2]),
      );
    });
  });
}

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

Uint8List buildBackup({
  List<ArchiveFile> illustrationEntries = const <ArchiveFile>[],
}) {
  final archive = Archive();

  final manifestBytes = utf8.encode(
    jsonEncode(<String, Object>{
      'format': 'read_book_hive_backup',
      'formatVersion': 1,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'boxes': boxNames,
    }),
  );

  archive.addFile(
    ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
  );

  for (final boxName in boxNames) {
    archive.addFile(archiveFile('hive/$boxName.hive', <int>[0]));
  }

  for (final entry in illustrationEntries) {
    archive.addFile(entry);
  }

  final encoded = ZipEncoder().encode(archive);

  if (encoded == null) {
    throw StateError('テスト用ZIPを作成できませんでした。');
  }

  return Uint8List.fromList(encoded);
}

ArchiveFile archiveFile(String name, List<int> bytes) {
  return ArchiveFile(name, bytes.length, Uint8List.fromList(bytes));
}
