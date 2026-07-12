import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
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

/// Hiveに保存されているアプリデータのバックアップと復元を行います。
///
/// 復元はHiveを開いている最中には行いません。
/// 選択されたバックアップを一時保存し、次回起動時に復元します。
class BackupService {
  static const String _backupFormat = 'read_book_hive_backup';
  static const int _backupFormatVersion = 1;

  static const String _pendingRestoreFileName = 'read_book_pending_restore.zip';

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

    try {
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

      try {
        // バックアップ内のHiveファイルを配置します。
        for (final boxName in _boxNames) {
          final bytes = restoredFiles[boxName];

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

      return 'バックアップの復元に失敗しました: $error';
    }
  }

  /// ZIPを読み込み、正しいRead Bookバックアップか確認します。
  static Map<String, Uint8List> _readAndValidateBackup(Uint8List zipBytes) {
    Archive archive;

    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (error) {
      throw FormatException('ZIPファイルを開けませんでした: $error');
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

    final result = <String, Uint8List>{};

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

      result[boxName] = _contentToBytes(targetFile.content);
    }

    return result;
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
