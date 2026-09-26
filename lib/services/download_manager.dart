import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/download_job.dart';
import '../models/work.dart';
import 'background_download_service.dart';
import 'novel_repository.dart';

class DownloadProgress {
  final String workId;
  final int done;
  final int total;
  final bool isRunning;

  const DownloadProgress({
    required this.workId,
    required this.done,
    required this.total,
    required this.isRunning,
  });
}

class DownloadManager {
  DownloadManager._(this._repository) {
    if (Platform.isIOS) {
      final service = BackgroundDownloadService(
        _repository,
        _handleBackgroundProgress,
      );

      _backgroundService = service;
      unawaited(service.initialize());
    }
  }

  static DownloadManager? _instance;

  static DownloadManager init(NovelRepository repository) {
    return _instance ??= DownloadManager._(repository);
  }

  static DownloadManager get instance {
    final instance = _instance;

    if (instance == null) {
      throw StateError('main.dartでDownloadManager.init()を呼んでください');
    }

    return instance;
  }

  final NovelRepository _repository;
  BackgroundDownloadService? _backgroundService;

  final Map<String, _ActiveDownload> _active = {};
  final Map<String, DownloadProgress> _backgroundProgress = {};

  Box<DownloadJob> get _jobBox => Hive.box<DownloadJob>('download_jobs');

  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressController.stream;

  DownloadProgress progressOf(String workId) {
    final background = _backgroundProgress[workId];

    if (background != null) {
      return background;
    }

    final active = _active[workId];

    if (active != null) {
      return active.toProgress(workId);
    }

    final job = _jobBox.get(workId);

    if (job != null && !job.isCompleted) {
      return DownloadProgress(
        workId: workId,
        done: job.doneCount,
        total: job.totalCount,
        isRunning: false,
      );
    }

    return DownloadProgress(
      workId: workId,
      done: 0,
      total: 0,
      isRunning: false,
    );
  }

  bool isDownloading(String workId) {
    return _active.containsKey(workId) ||
        (_backgroundProgress[workId]?.isRunning ?? false);
  }

  Future<void> downloadSingle({
    required Work work,
    required int episodeNo,
    required String episodeTitle,
    String publishedAt = '',
  }) async {
    if (_repository.isDownloaded(work, episodeNo)) {
      if (publishedAt.trim().isNotEmpty) {
        await _repository.updateDownloadPublishedDate(
          work: work,
          episodeNo: episodeNo,
          publishedAt: publishedAt,
        );
      }

      return;
    }

    await _repository.downloadEpisode(
      work: work,
      episodeNo: episodeNo,
      episodeTitle: episodeTitle,
      publishedAt: publishedAt,
    );

    _progressController.add(
      DownloadProgress(
        workId: work.workId,
        done: 1,
        total: 1,
        isRunning: false,
      ),
    );
  }

  Future<bool> enqueueBulk({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {
    if (isDownloading(work.workId)) {
      return false;
    }

    await _repository.updateDownloadPublishedDates(
      work: work,
      episodeList: episodeList,
    );

    final undownloaded = episodeList.where((entry) {
      final episodeNo = int.tryParse(entry['episodeNo'] ?? '') ?? 0;
      return !_repository.isDownloaded(work, episodeNo);
    }).toList();

    if (undownloaded.isEmpty) {
      return false;
    }

    if (Platform.isIOS) {
      final service = _backgroundService;

      if (service == null) {
        throw StateError('iOSバックグラウンドサービスが初期化されていません');
      }

      return service.enqueueBulk(work: work, episodeList: undownloaded);
    }

    return _enqueueForegroundBulk(work: work, episodeList: undownloaded);
  }

  Future<bool> _enqueueForegroundBulk({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {
    final active = _ActiveDownload(total: episodeList.length);

    _active[work.workId] = active;
    _emit(work.workId);

    final job = DownloadJob(
      workId: work.workId,
      totalCount: episodeList.length,
      doneCount: 0,
      startedAt: DateTime.now(),
      isCompleted: false,
    );

    await _jobBox.put(work.workId, job);

    unawaited(_runBulk(work, episodeList, job));

    return true;
  }

  Future<void> _runBulk(
    Work work,
    List<Map<String, String>> episodeList,
    DownloadJob job,
  ) async {
    final active = _active[work.workId];

    if (active == null) {
      return;
    }

    for (var index = 0; index < episodeList.length; index++) {
      final entry = episodeList[index];
      final episodeNo = int.tryParse(entry['episodeNo'] ?? '') ?? index + 1;
      final title = entry['title'] ?? '第$episodeNo話';

      final publishedAt =
          entry['publishedAt'] ??
          entry['update'] ??
          entry['published'] ??
          entry['updatedAt'] ??
          '';

      if (!_repository.isDownloaded(work, episodeNo)) {
        try {
          await _repository.downloadEpisode(
            work: work,
            episodeNo: episodeNo,
            episodeTitle: title,
            publishedAt: publishedAt,
          );
        } catch (_) {
          // 個別話の失敗は無視して次の話へ進みます。
        }

        await Future<void>.delayed(const Duration(milliseconds: 800));
      } else if (publishedAt.trim().isNotEmpty) {
        await _repository.updateDownloadPublishedDate(
          work: work,
          episodeNo: episodeNo,
          publishedAt: publishedAt,
        );
      }

      active.done = index + 1;
      job.doneCount = active.done;

      await job.save();
      _emit(work.workId);
    }

    job.isCompleted = true;
    await job.save();

    _active.remove(work.workId);
    _emit(work.workId);
  }

  void _handleBackgroundProgress(
    String workId,
    int done,
    int total,
    bool isRunning,
  ) {
    final progress = DownloadProgress(
      workId: workId,
      done: done,
      total: total,
      isRunning: isRunning,
    );

    if (isRunning) {
      _backgroundProgress[workId] = progress;
    } else {
      _backgroundProgress.remove(workId);
    }

    _progressController.add(progress);
  }

  void _emit(String workId) {
    _progressController.add(progressOf(workId));
  }

  List<DownloadJob> get incompleteJobs {
    return _jobBox.values.where((job) => !job.isCompleted).toList();
  }

  Future<void> resumeJob(DownloadJob job) async {
    final work = _repository.getWork(job.workId);

    if (work == null) {
      await _jobBox.delete(job.workId);
      return;
    }

    final episodeList = await _repository.fetchEpisodeList(work);

    await enqueueBulk(work: work, episodeList: episodeList);
  }

  Future<void> discardJob(DownloadJob job) async {
    await _jobBox.delete(job.workId);
    _backgroundProgress.remove(job.workId);
  }
}

class _ActiveDownload {
  _ActiveDownload({required this.total});

  final int total;
  int done = 0;

  DownloadProgress toProgress(String workId) {
    return DownloadProgress(
      workId: workId,
      done: done,
      total: total,
      isRunning: done < total,
    );
  }
}
