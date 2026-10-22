import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/download.dart';
import '../models/download_job.dart';
import '../models/episode.dart';
import '../models/favorite.dart';
import '../models/history_entry.dart';
import '../models/read_mark.dart';
import '../models/saved_search.dart';
import '../models/work.dart';
import 'illustration_storage_service.dart';

/// Hiveに保存されているアプリデータのバックアップと復元を行います。
///
/// 復元はHiveを開いている最中には行いません。
/// 選択されたバックアップを一時保存し、次回起動時に復元します。
class BackupService {
  static const String _backupFormat = 'read_book_hive_backup';
  static const int _backupFormatVersion = 1;

  static const String _pendingRestoreFileName = 'read_book_pending_restore.zip';

  static const int _maximumBackupArchiveBytes = 512 * 1024 * 1024;
  static const int _maximumBackupEntries = 50000;
  static const int _maximumBackupExpandedBytes = 2 * 1024 * 1024 * 1024;
  static const int _maximumManifestBytes = 64 * 1024;
  static const int _maximumHiveFileBytes = 512 * 1024 * 1024;
  static const int _maximumIllustrationBytes = 20 * 1024 * 1024;

  static const List<String> _boxNames = [
    'works',
    'episodes',
    'favorites',
    'saved_searches',
    'history',
    'download_jobs',
    'downloads',
    'read_marks',
  ];

  /// Hiveの書き込みをすべてディスクへ反映します。
  Future<void> _flushAllBoxes() async {
    await Future.wait<void>([
      Hive.box<Work>('works').flush(),
      Hive.box<Episode>('episodes').flush(),
      Hive.box<Favorite>('favorites').flush(),
      Hive.box<SavedSearch>('saved_searches').flush(),
      Hive.box<HistoryEntry>('history').flush(),
      Hive.box<DownloadJob>('download_jobs').flush(),
      Hive.box<Download>('downloads').flush(),
      Hive.box<ReadMark>('read_marks').flush(),
    ]);
  }

  /// 開かれている各Boxの保存ファイルを取得します。
  Map<String, File> _getHiveFiles() {
    final boxPaths = <String, String?>{
      'works': Hive.box<Work>('works').path,
      'episodes': Hive.box<Episode>('episodes').path,
      'favorites': Hive.box<Favorite>('favorites').path,
      'saved_searches': Hive.box<SavedSearch>('saved_searches').path,
      'history': Hive.box<HistoryEntry>('history').path,
      'download_jobs': Hive.box<DownloadJob>('download_jobs').path,
      'downloads': Hive.box<Download>('downloads').path,
      'read_marks': Hive.box<ReadMark>('read_marks').path,
    };

    final result = <String, File>{};

    for (final entry in boxPaths.entries) {
      final path = entry.value;

      if (path == null || path.trim().isEmpty) {
        throw StateError('Hive Box "${entry.key}" の保存場所を取得できませんでした。');
      }

      result[entry.key] = File(path);
    }

    return result;
  }

  /// Application Support内の挿絵ファイルをZIPへ追加します。
  ///
  /// ZIP内ではOSに依存しない「/」区切りの相対パスを使用します。
  Future<void> _addIllustrationsToArchive(Archive archive) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final illustrationDirectory = Directory(
      '${supportDirectory.path}'
      '${Platform.pathSeparator}'
      '${IllustrationStorageService.directoryName}',
    );

    if (!await illustrationDirectory.exists()) {
      return;
    }

    final rootPrefix = '${illustrationDirectory.path}${Platform.pathSeparator}';

    await for (final entity in illustrationDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      if (!entity.path.startsWith(rootPrefix)) {
        throw FileSystemException('挿絵ファイルの保存場所が不正です。', entity.path);
      }

      final relativePath = entity.path
          .substring(rootPrefix.length)
          .split(Platform.pathSeparator)
          .join('/');

      if (relativePath.isEmpty) {
        continue;
      }

      final bytes = await entity.readAsBytes();

      archive.addFile(
        ArchiveFile('illustrations/$relativePath', bytes.length, bytes),
      );
    }
  }

  /// バックアップZIPを作成します。
  Future<File> createBackupFile() async {
    await _flushAllBoxes();

    final hiveFiles = _getHiveFiles();
    final archive = Archive();

    final manifest = <String, dynamic>{
      'format': _backupFormat,
      'formatVersion': _backupFormatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'boxes': _boxNames,
      'illustrations': true,
    };

    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );

    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    for (final boxName in _boxNames) {
      final hiveFile = hiveFiles[boxName];

      if (hiveFile == null || !await hiveFile.exists()) {
        throw FileSystemException(
          'Hiveファイルが見つかりません。',
          hiveFile?.path ?? boxName,
        );
      }

      final bytes = await hiveFile.readAsBytes();

      archive.addFile(ArchiveFile('hive/$boxName.hive', bytes.length, bytes));
    }

    await _addIllustrationsToArchive(archive);

    final zipBytes = ZipEncoder().encode(archive);

    if (zipBytes == null) {
      throw StateError('バックアップZIPの作成に失敗しました。');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    final backupDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}read_book_backup',
    );

    await backupDirectory.create(recursive: true);

    final now = DateTime.now();
    final fileName =
        'read_book_backup_'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.zip';

    final backupFile = File(
      '${backupDirectory.path}${Platform.pathSeparator}$fileName',
    );

    await backupFile.writeAsBytes(zipBytes, flush: true);

    return backupFile;
  }

  /// バックアップZIPを作成し、iOSの共有画面を開きます。
  ///
  /// 共有画面から「ファイルに保存」を選択してください。
  Future<void> createAndShareBackup({required Rect sharePositionOrigin}) async {
    final backupFile = await createBackupFile();

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(backupFile.path)],
        subject: 'Read Book バックアップ',
        title: 'Read Book バックアップ',
        text: 'Read Bookのバックアップファイルです。',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// 「ファイル」アプリなどからバックアップZIPを選択し、
  /// 次回起動時の復元ファイルとして保存します。
  ///
  /// ファイル選択がキャンセルされた場合はfalseを返します。
  Future<bool> selectAndStageRestoreFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return false;
    }

    final selectedFile = result.files.single;

    _validateBackupArchiveSize(selectedFile.size);

    Uint8List bytes;

    if (selectedFile.bytes != null) {
      bytes = selectedFile.bytes!;
    } else {
      final path = selectedFile.path;

      if (path == null || path.trim().isEmpty) {
        throw const FormatException('選択したバックアップファイルを読み込めませんでした。');
      }

      bytes = await File(path).readAsBytes();
    }

    // 保存する前にバックアップの形式を検証します。
    _readAndValidateBackup(bytes);

    final supportDirectory = await getApplicationSupportDirectory();
    await supportDirectory.create(recursive: true);

    final pendingFile = File(
      '${supportDirectory.path}'
      '${Platform.pathSeparator}'
      '$_pendingRestoreFileName',
    );

    final temporaryFile = File('${pendingFile.path}.tmp');

    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }

    await temporaryFile.writeAsBytes(bytes, flush: true);

    if (await pendingFile.exists()) {
      await pendingFile.delete();
    }

    await temporaryFile.rename(pendingFile.path);

    return true;
  }

  /// 次回起動時に保留中のバックアップを復元します。
  ///
  /// 必ずHive.initFlutter()より前に呼び出してください。
  static Future<String?> applyPendingRestoreIfNeeded() async {
    final supportDirectory = await getApplicationSupportDirectory();

    final pendingFile = File(
      '${supportDirectory.path}'
      '${Platform.pathSeparator}'
      '$_pendingRestoreFileName',
    );

    if (!await pendingFile.exists()) {
      return null;
    }

    Directory? rollbackDirectory;
    Directory? stagedIllustrationDirectory;
    Directory? illustrationDirectory;
    var illustrationsChanged = false;

    try {
      final pendingSize = await pendingFile.length();
      _validateBackupArchiveSize(pendingSize);

      final backupBytes = await pendingFile.readAsBytes();
      final restoredFiles = _readAndValidateBackup(backupBytes);

      final documentsDirectory = await getApplicationDocumentsDirectory();

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      rollbackDirectory = Directory(
        '${supportDirectory.path}'
        '${Platform.pathSeparator}'
        'restore_rollback_$timestamp',
      );

      await rollbackDirectory.create(recursive: true);

      // 現在のHiveファイルをロールバック用に保存します。
      for (final boxName in _boxNames) {
        final currentFile = File(
          '${documentsDirectory.path}'
          '${Platform.pathSeparator}'
          '$boxName.hive',
        );

        if (await currentFile.exists()) {
          await currentFile.copy(
            '${rollbackDirectory.path}'
            '${Platform.pathSeparator}'
            '$boxName.hive',
          );
        }
      }

      illustrationDirectory = Directory(
        '${supportDirectory.path}'
        '${Platform.pathSeparator}'
        '${IllustrationStorageService.directoryName}',
      );

      stagedIllustrationDirectory = Directory(
        '${supportDirectory.path}'
        '${Platform.pathSeparator}'
        'restore_staged_illustrations_$timestamp',
      );

      if (await stagedIllustrationDirectory.exists()) {
        await stagedIllustrationDirectory.delete(recursive: true);
      }

      await stagedIllustrationDirectory.create(recursive: true);

      for (final entry in restoredFiles.illustrationFiles.entries) {
        final relativePlatformPath = entry.key
            .split('/')
            .join(Platform.pathSeparator);

        final targetFile = File(
          '${stagedIllustrationDirectory.path}'
          '${Platform.pathSeparator}'
          '$relativePlatformPath',
        );

        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(entry.value, flush: true);
      }

      try {
        // バックアップ内のHiveファイルを配置します。
        for (final boxName in _boxNames) {
          final bytes = restoredFiles.hiveFiles[boxName];

          if (bytes == null) {
            throw FormatException('バックアップ内に $boxName のデータがありません。');
          }

          final targetFile = File(
            '${documentsDirectory.path}'
            '${Platform.pathSeparator}'
            '$boxName.hive',
          );

          final temporaryFile = File('${targetFile.path}.restore_tmp');

          if (await temporaryFile.exists()) {
            await temporaryFile.delete();
          }

          await temporaryFile.writeAsBytes(bytes, flush: true);

          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          await temporaryFile.rename(targetFile.path);
        }

        final rollbackIllustrationDirectory = Directory(
          '${rollbackDirectory.path}'
          '${Platform.pathSeparator}'
          'illustrations',
        );

        illustrationsChanged = true;

        if (await illustrationDirectory.exists()) {
          await illustrationDirectory.rename(
            rollbackIllustrationDirectory.path,
          );
        }

        await stagedIllustrationDirectory.rename(illustrationDirectory.path);
      } catch (_) {
        // 復元途中で失敗した場合は元のファイルへ戻します。
        for (final boxName in _boxNames) {
          final targetFile = File(
            '${documentsDirectory.path}'
            '${Platform.pathSeparator}'
            '$boxName.hive',
          );

          final rollbackFile = File(
            '${rollbackDirectory.path}'
            '${Platform.pathSeparator}'
            '$boxName.hive',
          );

          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          if (await rollbackFile.exists()) {
            await rollbackFile.copy(targetFile.path);
          }
        }

        if (illustrationsChanged) {
          final rollbackIllustrationDirectory = Directory(
            '${rollbackDirectory.path}'
            '${Platform.pathSeparator}'
            'illustrations',
          );

          if (await illustrationDirectory.exists()) {
            await illustrationDirectory.delete(recursive: true);
          }

          if (await rollbackIllustrationDirectory.exists()) {
            await rollbackIllustrationDirectory.rename(
              illustrationDirectory.path,
            );
          }
        }

        rethrow;
      }

      await pendingFile.delete();

      if (await rollbackDirectory.exists()) {
        await rollbackDirectory.delete(recursive: true);
      }

      return 'バックアップからデータを復元しました。';
    } catch (error) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final failedFile = File(
        '${supportDirectory.path}'
        '${Platform.pathSeparator}'
        'read_book_failed_restore_$timestamp.zip',
      );

      try {
        if (await pendingFile.exists()) {
          await pendingFile.rename(failedFile.path);
        }
      } catch (_) {
        // 失敗ファイルの移動に失敗してもアプリ起動は続行します。
      }

      if (rollbackDirectory != null && await rollbackDirectory.exists()) {
        try {
          await rollbackDirectory.delete(recursive: true);
        } catch (_) {
          // ロールバックフォルダーの削除失敗は無視します。
        }
      }

      if (stagedIllustrationDirectory != null &&
          await stagedIllustrationDirectory.exists()) {
        try {
          await stagedIllustrationDirectory.delete(recursive: true);
        } catch (_) {
          // 一時挿絵フォルダーの削除失敗は無視します。
        }
      }

      return 'バックアップの復元に失敗しました: $error';
    }
  }

  /// ZIPを読み込み、正しいRead Bookバックアップか確認します。
  static _ValidatedBackup _readAndValidateBackup(
    Uint8List zipBytes, {
    int maximumArchiveBytes = _maximumBackupArchiveBytes,
    int maximumEntries = _maximumBackupEntries,
    int maximumExpandedBytes = _maximumBackupExpandedBytes,
    int maximumManifestBytes = _maximumManifestBytes,
    int maximumHiveFileBytes = _maximumHiveFileBytes,
    int maximumIllustrationBytes = _maximumIllustrationBytes,
  }) {
    _validateBackupArchiveSize(
      zipBytes.length,
      maximumBytes: maximumArchiveBytes,
    );

    Archive archive;

    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (error) {
      throw FormatException('ZIPファイルを開けませんでした: $error');
    }

    if (archive.files.length > maximumEntries) {
      throw FormatException(
        'バックアップ内のファイル数が上限を超えています: '
        '${archive.files.length} 件',
      );
    }

    var expandedBytes = 0;

    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }

      if (file.size < 0) {
        throw FormatException('バックアップ内のファイル容量が不正です: ${file.name}');
      }

      expandedBytes += file.size;

      if (expandedBytes > maximumExpandedBytes) {
        throw FormatException(
          'バックアップの展開後容量が上限を超えています: '
          '$expandedBytes バイト',
        );
      }
    }

    ArchiveFile? manifestFile;

    for (final file in archive.files) {
      if (file.isFile && file.name == 'manifest.json') {
        manifestFile = file;
        break;
      }
    }

    if (manifestFile == null) {
      throw const FormatException('Read Bookのバックアップファイルではありません。');
    }

    if (manifestFile.size > maximumManifestBytes) {
      throw FormatException(
        'バックアップ情報の容量が上限を超えています: '
        '${manifestFile.size} バイト',
      );
    }

    final manifestBytes = _contentToBytes(manifestFile.content);
    final manifestText = utf8.decode(manifestBytes);

    final decodedManifest = jsonDecode(manifestText);

    if (decodedManifest is! Map) {
      throw const FormatException('バックアップ情報の形式が正しくありません。');
    }

    if (decodedManifest['format'] != _backupFormat) {
      throw const FormatException('Read Bookのバックアップファイルではありません。');
    }

    final formatVersion = decodedManifest['formatVersion'];

    if (formatVersion != _backupFormatVersion) {
      throw FormatException(
        '対応していないバックアップ形式です。'
        ' バージョン: $formatVersion',
      );
    }

    final hiveFiles = <String, Uint8List>{};

    for (final boxName in _boxNames) {
      final expectedName = 'hive/$boxName.hive';
      ArchiveFile? targetFile;

      for (final file in archive.files) {
        if (file.isFile && file.name == expectedName) {
          targetFile = file;
          break;
        }
      }

      if (targetFile == null) {
        throw FormatException('バックアップ内に $boxName のデータがありません。');
      }

      if (targetFile.size > maximumHiveFileBytes) {
        throw FormatException(
          'バックアップ内の $boxName の容量が上限を超えています: '
          '${targetFile.size} バイト',
        );
      }

      hiveFiles[boxName] = _contentToBytes(targetFile.content);
    }

    final illustrationFiles = <String, Uint8List>{};

    for (final file in archive.files) {
      final name = file.name;

      if (!name.startsWith('illustrations')) {
        continue;
      }

      if (!file.isFile) {
        continue;
      }

      final relativePath = _validateIllustrationEntryName(name);

      if (illustrationFiles.containsKey(relativePath)) {
        throw FormatException('バックアップ内に同じ挿絵ファイルが複数あります: $relativePath');
      }

      if (file.size > maximumIllustrationBytes) {
        throw FormatException(
          'バックアップ内の挿絵容量が上限を超えています: '
          '$relativePath (${file.size} バイト)',
        );
      }

      illustrationFiles[relativePath] = _contentToBytes(file.content);
    }

    return _ValidatedBackup(
      hiveFiles: hiveFiles,
      illustrationFiles: illustrationFiles,
    );
  }

  /// ZIP内の挿絵エントリ名を検証し、安全な相対パスを返します。
  static String _validateIllustrationEntryName(String name) {
    const prefix = 'illustrations/';

    if (!name.startsWith(prefix)) {
      throw FormatException('挿絵ファイルのパスが不正です: $name');
    }

    if (name.contains(r'\') || name.startsWith('/')) {
      throw FormatException('挿絵ファイルのパスが不正です: $name');
    }

    final relativePath = name.substring(prefix.length);
    final segments = relativePath.split('/');

    if (relativePath.isEmpty ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              segment.contains(':') ||
              segment.contains('\u0000'),
        )) {
      throw FormatException('挿絵ファイルのパスが不正です: $name');
    }

    return relativePath;
  }

  /// テストでバックアップの容量制限を確認するための入口です。
  @visibleForTesting
  static void validateBackupForTesting(
    Uint8List zipBytes, {
    int maximumArchiveBytes = _maximumBackupArchiveBytes,
    int maximumEntries = _maximumBackupEntries,
    int maximumExpandedBytes = _maximumBackupExpandedBytes,
    int maximumManifestBytes = _maximumManifestBytes,
    int maximumHiveFileBytes = _maximumHiveFileBytes,
    int maximumIllustrationBytes = _maximumIllustrationBytes,
  }) {
    _readAndValidateBackup(
      zipBytes,
      maximumArchiveBytes: maximumArchiveBytes,
      maximumEntries: maximumEntries,
      maximumExpandedBytes: maximumExpandedBytes,
      maximumManifestBytes: maximumManifestBytes,
      maximumHiveFileBytes: maximumHiveFileBytes,
      maximumIllustrationBytes: maximumIllustrationBytes,
    );
  }

  /// テストでZIP検証結果を確認するための読み取り専用入口です。
  @visibleForTesting
  static Map<String, Uint8List> readIllustrationsForTesting(
    Uint8List zipBytes,
  ) {
    return Map<String, Uint8List>.unmodifiable(
      _readAndValidateBackup(zipBytes).illustrationFiles,
    );
  }

  static void _validateBackupArchiveSize(
    int size, {
    int maximumBytes = _maximumBackupArchiveBytes,
  }) {
    if (size <= 0 || size > maximumBytes) {
      throw FormatException('バックアップZIPの容量が不正です: $size バイト');
    }
  }

  static Uint8List _contentToBytes(dynamic content) {
    if (content is Uint8List) {
      return content;
    }

    if (content is List<int>) {
      return Uint8List.fromList(content);
    }

    throw const FormatException('バックアップ内のデータを読み込めませんでした。');
  }
}

class _ValidatedBackup {
  const _ValidatedBackup({
    required this.hiveFiles,
    required this.illustrationFiles,
  });

  final Map<String, Uint8List> hiveFiles;
  final Map<String, Uint8List> illustrationFiles;
}
