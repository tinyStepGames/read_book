import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/download_job.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/screens/work_detail_screen.dart';
import 'package:read_book/services/download_manager.dart';
import 'package:read_book/services/download_refresh_planner.dart';
import 'package:read_book/services/download_refresh_runner.dart';
import 'package:read_book/services/novel_repository.dart';

String sourceIdFor(Work work) => work.siteIndex == Site.narou.index
    ? 'https://ncode.syosetu.com/n3380le/1/'
    : '2912051606897546666';

Work createWork(Site site) => Work(
  workId: site == Site.narou ? 'n3380le' : '2912051605992818100',
  siteIndex: site.index,
  title: '本文更新テスト作品',
  author: '作者',
  genre: '',
  summary: '',
  totalEpisodeCount: 1,
  checkedEpisodeCount: 1,
  lastUpdatedAt: DateTime.utc(2026, 1, 1),
  isCompleted: false,
);

DownloadRefreshBatchResult makeResult(
  Work work,
  List<DownloadRefreshOutcome> outcomes,
) => DownloadRefreshBatchResult([
  for (var index = 0; index < outcomes.length; index++)
    DownloadRefreshItemResult(
      item: DownloadRefreshItem(
        episodeNo: index + 1,
        decision: DownloadRefreshDecision.refresh,
        latestEntry: {
          'episodeNo': '${index + 1}',
          'sourceId': sourceIdFor(work),
          'title': '更新後の第${index + 1}話',
        },
      ),
      outcome: outcomes[index],
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
  Future<void> refreshWorkDetails(Work work) async {}

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(Work work) async {
    episodeListCalls++;
    return [
      {'episodeNo': '1', 'title': '更新前の第1話', 'sourceId': sourceIdFor(work)},
    ];
  }

  @override
  Future<void> updateDownloadPublishedDates({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {}

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
  group('作品詳細画面から保存済み本文を更新', () {
    late Directory directory;
    late _Repository repository;

    final updateButton = find.byKey(const ValueKey('refresh-downloaded-work'));

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp(
        'work_detail_download_refresh_test_',
      );
      Hive.init(directory.path);
      if (!Hive.isAdapterRegistered(6)) {
        Hive.registerAdapter(DownloadJobAdapter());
      }
      await Hive.openBox<DownloadJob>('download_jobs');
      repository = _Repository();
      DownloadManager.init(repository);
    });

    setUp(() {
      repository.saved = null;
      repository.hasDownloads = true;
      repository.calls = 0;
      repository.episodeListCalls = 0;
      repository.receivedForce = null;
      repository.receivedWork = null;
      repository.token = null;
      repository.progress = null;
      repository.handler = () async =>
          makeResult(repository.saved!, [DownloadRefreshOutcome.updated]);
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    Future<void> showScreen(WidgetTester tester, Site site) async {
      final work = createWork(site);
      repository.saved = work;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkDetailScreen(repository: repository, work: work),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(updateButton);
      await tester.pumpAndSettle();
      expect(repository.calls, 0);
      await tester.tap(find.text('更新を開始'));
    }

    for (final site in [Site.narou, Site.kakuyomu]) {
      testWidgets('${site.name}で確認後に更新し結果とタイトルを反映する', (tester) async {
        await showScreen(tester, site);
        await confirm(tester);
        await tester.pumpAndSettle();

        expect(repository.calls, 1);
        expect(repository.receivedForce, isFalse);
        expect(repository.receivedWork, same(repository.saved));
        expect(repository.token, isNotNull);
        expect(repository.progress, isNotNull);
        expect(find.text('本文更新: 1話'), findsOneWidget);

        await tester.tap(find.text('閉じる'));
        await tester.pumpAndSettle();

        expect(find.text('更新後の第1話'), findsOneWidget);
        expect(repository.episodeListCalls, 1);
        expect(
          tester.widget<OutlinedButton>(updateButton).onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('保存済み本文がなければボタンを無効にする', (tester) async {
      repository.hasDownloads = false;
      await showScreen(tester, Site.narou);
      expect(tester.widget<OutlinedButton>(updateButton).onPressed, isNull);
      expect(repository.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('確認をキャンセルしたら更新しない', (tester) async {
      await showScreen(tester, Site.narou);
      await tester.tap(updateButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(repository.calls, 0);
      expect(tester.widget<OutlinedButton>(updateButton).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('再取得オプションをRepositoryへ渡す', (tester) async {
      await showScreen(tester, Site.kakuyomu);
      await tester.tap(updateButton);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('force-download-refresh')));
      await tester.pump();
      await tester.tap(find.text('更新を開始'));
      await tester.pumpAndSettle();

      expect(repository.receivedForce, isTrue);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('進捗と中止要求をRepositoryへ接続する', (tester) async {
      final pending = Completer<DownloadRefreshBatchResult>();
      repository.handler = () => pending.future;
      await showScreen(tester, Site.narou);
      await confirm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repository.calls, 1);
      repository.progress!(1, 2);
      await tester.pump();
      expect(find.text('確認済み: 1/2話'), findsOneWidget);

      await tester.tap(find.text('中止'));
      await tester.pump();
      expect(repository.token!.isRequested, isTrue);

      pending.complete(
        makeResult(repository.saved!, [
          DownloadRefreshOutcome.updated,
          DownloadRefreshOutcome.canceled,
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('本文更新: 1話'), findsOneWidget);
      expect(find.text('中止: 1話'), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(updateButton).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('全体失敗後も再操作でき以前の目次を維持する', (tester) async {
      repository.handler = () async => throw StateError('test refresh failure');
      await showScreen(tester, Site.narou);
      await confirm(tester);
      await tester.pumpAndSettle();

      expect(find.text('本文更新を完了できませんでした'), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();

      expect(find.text('更新前の第1話'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(updateButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('実行中の画面破棄で中止を要求し遅延完了を無視する', (tester) async {
      final pending = Completer<DownloadRefreshBatchResult>();
      repository.handler = () => pending.future;
      await showScreen(tester, Site.narou);
      await confirm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final work = repository.saved!;
      final token = repository.token!;
      await tester.pumpWidget(const SizedBox.shrink());

      expect(token.isRequested, isTrue);
      pending.complete(makeResult(work, [DownloadRefreshOutcome.canceled]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }, skip: Platform.isIOS);
}
