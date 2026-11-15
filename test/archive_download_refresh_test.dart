import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/download_job.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/screens/archive_screen.dart';
import 'package:read_book/services/download_manager.dart';
import 'package:read_book/services/download_refresh_planner.dart';
import 'package:read_book/services/download_refresh_runner.dart';
import 'package:read_book/services/novel_repository.dart';

Work createWork(Site site) => Work(
  workId: site == Site.narou ? 'n3380le' : '2912051605992818100',
  siteIndex: site.index,
  title: '書庫の本文更新テスト',
  author: '作者',
  genre: '',
  summary: '',
  totalEpisodeCount: 1,
  checkedEpisodeCount: 1,
  lastUpdatedAt: DateTime.utc(2026, 1, 1),
  isCompleted: false,
);

DownloadRefreshBatchResult makeResult() => DownloadRefreshBatchResult(const [
  DownloadRefreshItemResult(
    item: DownloadRefreshItem(
      episodeNo: 1,
      decision: DownloadRefreshDecision.refresh,
      latestEntry: {
        'episodeNo': '1',
        'title': '結果だけにある仮タイトル',
        'sourceId': 'source-1',
      },
    ),
    outcome: DownloadRefreshOutcome.updated,
  ),
]);

class _Repository extends NovelRepository {
  Work? saved;
  bool hasDownloads = true;
  int calls = 0;
  int episodeListCalls = 0;
  bool? receivedForce;
  Work? receivedWork;
  DownloadRefreshCancellation? token;
  void Function(int, int)? progress;
  late Future<DownloadRefreshBatchResult> Function() handler;

  @override
  Work? getWork(String workId) => saved?.workId == workId ? saved : null;

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(Work work) async {
    episodeListCalls++;
    return [
      {'episodeNo': '1', 'title': '保存済みの第1話'},
    ];
  }

  @override
  bool hasAnyDownload(String workId) => hasDownloads;

  @override
  bool isDownloaded(Work work, int episodeNo) => hasDownloads;

  @override
  bool isEpisodeRead(String workId, int episodeNo) => false;

  @override
  Future<DownloadRefreshBatchResult> refreshDownloadedWork({
    required Work work,
    bool forceRefresh = false,
    DownloadRefreshCancellation? cancellation,
    void Function(int completed, int total)? onProgress,
    Future<bool> Function(DownloadRefreshPlan plan)? confirmPlan,
  }) {
    calls++;
    receivedWork = work;
    receivedForce = forceRefresh;
    token = cancellation;
    progress = onProgress;
    return handler();
  }
}

void main() {
  late Directory directory;
  late Box<Work> works;
  late Box<Download> downloads;
  late _Repository repository;

  final button = find.byKey(const ValueKey('archive-refresh-downloaded-work'));
  final informationButton = find.byKey(
    const ValueKey('archive-refresh-work-information'),
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'archive_download_refresh_test_',
    );
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WorkAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(DownloadJobAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(DownloadAdapter());
    }
    works = await Hive.openBox<Work>('works');
    downloads = await Hive.openBox<Download>('downloads');
    await Hive.openBox<DownloadJob>('download_jobs');
    repository = _Repository();
    DownloadManager.init(repository);
  });

  setUp(() async {
    await works.clear();
    await downloads.clear();
    repository.saved = null;
    repository.hasDownloads = true;
    repository.calls = 0;
    repository.episodeListCalls = 0;
    repository.receivedForce = null;
    repository.receivedWork = null;
    repository.token = null;
    repository.progress = null;
    repository.handler = () async => makeResult();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> showScreen(WidgetTester tester, Site site) async {
    final work = createWork(site);
    repository.saved = work;
    await tester.runAsync(() async {
      await works.put(work.workId, work);
      if (repository.hasDownloads) {
        await downloads.put(
          '${work.workId}_1',
          Download(
            workId: work.workId,
            episodeNo: 1,
            episodeTitle: '保存済みの第1話',
            body: '保存済み本文',
            downloadedAt: DateTime.utc(2026, 1, 1),
            sourceId: 'source-1',
            sourceUpdatedAt: 'version-1',
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadedWorkScreen(repository: repository, work: work),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, {bool force = false}) async {
    await tester.tap(button);
    await tester.pumpAndSettle();
    if (force) {
      await tester.tap(find.byKey(const ValueKey('force-download-refresh')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('更新を開始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final site in [Site.narou, Site.kakuyomu]) {
    testWidgets('${site.name}: 更新実行・結果表示と保存済みタイトルの表示追従', (tester) async {
      await showScreen(tester, site);
      final originalBody = downloads.values.single.body;

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(repository.receivedWork!.siteIndex, site.index);
      expect(repository.receivedForce, isFalse);
      expect(find.text('本文更新の結果'), findsOneWidget);
      expect(find.text('本文更新: 1話'), findsOneWidget);

      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();

      // 結果の目次タイトルだけでは、保存済み表示を上書きしません。
      expect(find.text('保存済みの第1話'), findsOneWidget);
      expect(find.text('結果だけにある仮タイトル'), findsNothing);
      expect(downloads.values.single.body, originalBody);

      // 実際に保存された各話タイトルへの追従を確認します。
      final work = repository.saved!;
      await tester.runAsync(() async {
        await downloads.put(
          '${work.workId}_1',
          Download(
            workId: work.workId,
            episodeNo: 1,
            episodeTitle: '更新後の第1話',
            body: '更新された本文',
            downloadedAt: DateTime.utc(2026, 1, 2),
            sourceId: 'source-1',
            sourceUpdatedAt: 'version-2',
          ),
        );
      });
      await tester.pumpAndSettle();

      expect(find.text('更新後の第1話'), findsOneWidget);
      expect(find.text('保存済みの第1話'), findsNothing);
      expect(downloads.length, 1);
      expect(repository.episodeListCalls, 1);
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('同じ更新日時でも再取得する指定を渡す', (tester) async {
    await showScreen(tester, Site.narou);
    await confirm(tester, force: true);
    await tester.pumpAndSettle();

    expect(repository.receivedForce, isTrue);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('確認でキャンセルした場合は更新しない', (tester) async {
    await showScreen(tester, Site.narou);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('保存済み本文がない場合は無効', (tester) async {
    repository.hasDownloads = false;
    await showScreen(tester, Site.narou);

    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(repository.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('全体失敗後も保存済み本文を維持して再操作できる', (tester) async {
    repository.handler = () async => throw StateError('test refresh failure');
    await showScreen(tester, Site.narou);
    await confirm(tester);
    await tester.pumpAndSettle();

    expect(find.text('本文更新を完了できませんでした'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    expect(downloads.values.single.body, '保存済み本文');
    expect(find.text('保存済みの第1話'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('重複実行を拒否し情報更新を無効化して中止を要求できる', (tester) async {
    final pending = Completer<DownloadRefreshBatchResult>();
    repository.handler = () => pending.future;
    await showScreen(tester, Site.narou);
    final callback = tester.widget<IconButton>(button).onPressed!;

    await confirm(tester);
    callback();
    await tester.pump();

    expect(repository.calls, 1);
    expect(tester.widget<IconButton>(informationButton).onPressed, isNull);
    expect(tester.widget<IconButton>(button).onPressed, isNull);

    repository.progress!(1, 2);
    await tester.pump();
    expect(find.text('確認済み: 1/2話'), findsOneWidget);

    await tester.tap(find.text('中止'));
    await tester.pump();
    expect(repository.token!.isRequested, isTrue);

    pending.complete(makeResult());
    await tester.pumpAndSettle();
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(informationButton).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('画面破棄で中止を要求し遅延完了を無視する', (tester) async {
    final pending = Completer<DownloadRefreshBatchResult>();
    repository.handler = () => pending.future;
    await showScreen(tester, Site.kakuyomu);
    await confirm(tester);

    final token = repository.token!;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(token.isRequested, isTrue);

    pending.complete(makeResult());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
