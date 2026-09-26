import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/download_job.dart';
import '../models/site.dart';
import '../models/work.dart';
import 'background_episode_parser.dart';
import 'novel_repository.dart';

typedef BackgroundDownloadProgressCallback =
    void Function(String workId, int done, int total, bool isRunning);

class BackgroundDownloadService {
  BackgroundDownloadService(this._repository, this._onProgress);

  static const String groupName = 'read_book_episode_downloads';
  static const String downloadDirectory = 'read_book_background';

  static const Map<String, String> _narouHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1',
    'Accept':
        'text/html,application/xhtml+xml,'
        'application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
  };

  static const Map<String, String> _kakuyomuHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1',
    'Accept':
        'text/html,application/xhtml+xml,'
        'application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
  };

  final NovelRepository _repository;
  final BackgroundDownloadProgressCallback _onProgress;
  final FileDownloader _downloader = FileDownloader();

  bool _initialized = false;
  Future<void>? _initializing;
  Future<void> _statusProcessing = Future<void>.value();

  Box<DownloadJob> get _jobBox => Hive.box<DownloadJob>('download_jobs');

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }

    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    _downloader.registerCallbacks(
      group: groupName,
      taskStatusCallback: _queueStatusUpdate,
    );

    // Dart側ではなくネイティブ側のHoldingQueueを使用します。
    // アプリがサスペンドされても、iOS側で1件ずつ処理されます。
    await _downloader.configure(
      globalConfig: (Config.holdingQueue, (1, 1, 1)),
      iOSConfig: (Config.resourceTimeout, const Duration(hours: 4)),
    );

    // リスナー登録後にstartを呼ぶ必要があります。
    // バックグラウンド中に完了した結果も、ここで再照合されます。
    await _downloader.start(autoCleanDatabase: true);

    _initialized = true;
  }

  Future<bool> enqueueBulk({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {
    await initialize();
    await _repository.saveWork(work);

    final tasks = <DownloadTask>[];
    final batchId = DateTime.now().microsecondsSinceEpoch.toString();

    for (var index = 0; index < episodeList.length; index++) {
      final entry = episodeList[index];
      final episodeNo = int.tryParse(entry['episodeNo'] ?? '') ?? index + 1;

      if (_repository.isDownloaded(work, episodeNo)) {
        continue;
      }

      final url = (entry['url'] ?? '').trim();

      if (url.isEmpty || Uri.tryParse(url)?.hasAbsolutePath != true) {
        continue;
      }

      final title = (entry['title'] ?? '').trim().isEmpty
          ? '第$episodeNo話'
          : entry['title']!.trim();

      final publishedAt =
          entry['publishedAt'] ??
          entry['update'] ??
          entry['published'] ??
          entry['updatedAt'] ??
          '';

      final taskId =
          'readbook_${work.siteIndex}_${work.workId}_${episodeNo}_$batchId';

      final metadata = jsonEncode(<String, dynamic>{
        'workId': work.workId,
        'siteIndex': work.siteIndex,
        'episodeNo': episodeNo,
        'episodeTitle': title,
        'publishedAt': publishedAt,
      });

      final site = Site.values[work.siteIndex];

      tasks.add(
        DownloadTask(
          taskId: taskId,
          url: url,
          headers: site == Site.narou ? _narouHeaders : _kakuyomuHeaders,
          filename: '$taskId.html',
          directory: downloadDirectory,
          baseDirectory: BaseDirectory.applicationSupport,
          group: groupName,
          updates: Updates.status,
          retries: 3,
          allowPause: true,
          priority: 5,
          metaData: metadata,
          displayName: title,
        ),
      );
    }

    if (tasks.isEmpty) {
      return false;
    }

    final job = DownloadJob(
      workId: work.workId,
      totalCount: tasks.length,
      doneCount: 0,
      startedAt: DateTime.now(),
      isCompleted: false,
    );

    await _jobBox.put(work.workId, job);

    _onProgress(work.workId, 0, tasks.length, true);

    final results = await _downloader.enqueueAll(tasks);
    final acceptedCount = results.where((accepted) => accepted).length;

    if (acceptedCount == 0) {
      _onProgress(work.workId, 0, tasks.length, false);
      return false;
    }

    return true;
  }

  void _queueStatusUpdate(TaskStatusUpdate update) {
    _statusProcessing = _statusProcessing
        .then<void>((_) => _handleStatusUpdate(update))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('バックグラウンド本文の取り込みに失敗しました: $error');
          debugPrintStack(stackTrace: stackTrace);
        });
  }

  Future<void> _handleStatusUpdate(TaskStatusUpdate update) async {
    if (update.task.group != groupName) {
      return;
    }

    if (update.status != TaskStatus.complete) {
      if (update.status == TaskStatus.failed ||
          update.status == TaskStatus.notFound ||
          update.status == TaskStatus.canceled) {
        final metadata = _decodeMetadata(update.task.metaData);
        final workId = metadata['workId']?.toString() ?? '';
        final job = _jobBox.get(workId);

        if (workId.isNotEmpty && job != null) {
          _onProgress(workId, job.doneCount, job.totalCount, false);
        }
      }

      return;
    }

    final metadata = _decodeMetadata(update.task.metaData);
    final workId = metadata['workId']?.toString() ?? '';
    final siteIndex = _toInt(metadata['siteIndex']);
    final episodeNo = _toInt(metadata['episodeNo']);
    final episodeTitle = metadata['episodeTitle']?.toString() ?? '第$episodeNo話';
    final publishedAt = metadata['publishedAt']?.toString() ?? '';

    if (workId.isEmpty ||
        episodeNo <= 0 ||
        siteIndex < 0 ||
        siteIndex >= Site.values.length) {
      await _deleteTemporaryFile(update.task);
      return;
    }

    final work = _repository.getWork(workId);

    if (work == null) {
      await _deleteTemporaryFile(update.task);
      return;
    }

    final alreadyDownloaded = _repository.isDownloaded(work, episodeNo);

    if (!alreadyDownloaded) {
      final filePath = await update.task.filePath();
      final file = File(filePath);

      if (!await file.exists()) {
        throw StateError('完了したHTMLファイルが見つかりません: $filePath');
      }

      final html = await file.readAsString();

      final body = BackgroundEpisodeParser.parse(
        site: Site.values[siteIndex],
        html: html,
      );

      await _repository.saveDownloadedEpisodeBody(
        work: work,
        episodeNo: episodeNo,
        episodeTitle: episodeTitle,
        body: body,
        publishedAt: publishedAt,
      );
    }

    final job = _jobBox.get(workId);

    if (job != null && !job.isCompleted) {
      if (!alreadyDownloaded) {
        job.doneCount = (job.doneCount + 1).clamp(0, job.totalCount);
      }

      if (job.doneCount >= job.totalCount) {
        job.doneCount = job.totalCount;
        job.isCompleted = true;
      }

      await job.save();

      _onProgress(workId, job.doneCount, job.totalCount, !job.isCompleted);
    }

    await _deleteTemporaryFile(update.task);
  }

  Map<String, dynamic> _decodeMetadata(String value) {
    try {
      final decoded = jsonDecode(value);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return const <String, dynamic>{};
    }

    return const <String, dynamic>{};
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  Future<void> _deleteTemporaryFile(Task task) async {
    try {
      final path = await task.filePath();
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('一時HTMLファイルを削除できませんでした: $error');
    }
  }
}
