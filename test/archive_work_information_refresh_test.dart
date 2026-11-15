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
import 'package:read_book/services/novel_repository.dart';
import 'package:read_book/services/search_request_controller.dart';

Work createWork(Site site, {bool updated = false}) {
  return Work(
    workId: site == Site.narou ? 'n3380le' : '2912051605992818100',
    siteIndex: site.index,
    title: updated ? '更新後の作品名' : '更新前の作品名',
    author: updated ? '新作者' : '旧作者',
    genre: updated ? '新ジャンル' : '旧ジャンル',
    summary: updated ? '短い新版' : '以前の長いあらすじです',
    totalEpisodeCount: updated ? 2 : 1,
    checkedEpisodeCount: 1,
    lastUpdatedAt: DateTime.utc(2026, 1, 1),
    isCompleted: updated,
    firstOpenedAt: DateTime.utc(2025, 12, 1),
  );
}

class _Repository extends NovelRepository {
  Work? saved;
  int narouCalls = 0;
  int kakuyomuCalls = 0;
  int episodeListCalls = 0;
  late Future<bool> Function(Work) handler;

  @override
  Work? getWork(String workId) {
    return saved?.workId == workId ? saved : null;
  }

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(Work work) async {
    episodeListCalls++;
    return [
      {'episodeNo': '1', 'title': '保存済みの第1話'},
    ];
  }

  @override
  bool hasAnyDownload(String workId) => true;

  @override
  bool isDownloaded(Work work, int episodeNo) => true;

  @override
  bool isEpisodeRead(String workId, int episodeNo) => false;

  @override
  Future<bool> refreshStoredNarouWorkDetails({required Work work}) {
    narouCalls++;
    return handler(work);
  }

  @override
  Future<bool> refreshStoredKakuyomuWorkDetails({required Work work}) {
    kakuyomuCalls++;
    return handler(work);
  }
}

void main() {
  late Directory directory;
  late Box<Work> works;
  late Box<Download> downloads;
  late _Repository repository;
  late SearchRequestController searchController;

  final button = find.byKey(const ValueKey('archive-refresh-work-information'));

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'archive_work_information_refresh_test_',
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
    repository.narouCalls = 0;
    repository.kakuyomuCalls = 0;
    repository.episodeListCalls = 0;
    repository.handler = (work) async {
      repository.saved = createWork(Site.values[work.siteIndex], updated: true);
      return true;
    };
    searchController = SearchRequestController();
  });

  tearDown(() {
    searchController.dispose();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> showScreen(
    WidgetTester tester,
    Work work, {
    bool list = false,
  }) async {
    repository.saved = work;
    await tester.runAsync(() async {
      await works.put(work.workId, work);
      await downloads.put(
        '${work.workId}_1',
        Download(
          workId: work.workId,
          episodeNo: 1,
          episodeTitle: '保存済みの第1話',
          body: '元の本文',
          downloadedAt: DateTime.utc(2026, 1, 1),
          sourceId: 'saved-source-id',
          sourceUpdatedAt: 'saved-revision',
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: list
            ? SiteArchiveScreen(
                repository: repository,
                site: Site.values[work.siteIndex],
                searchRequestController: searchController,
                onNavigateToSearch: () {},
              )
            : DownloadedWorkScreen(repository: repository, work: work),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final site in [Site.narou, Site.kakuyomu]) {
    testWidgets('${site.name}: タイトル・説明文・完結状態を更新する', (tester) async {
      final original = createWork(site);
      await showScreen(tester, original);
      final originalDownload = downloads.values.single;

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(repository.narouCalls, site == Site.narou ? 1 : 0);
      expect(repository.kakuyomuCalls, site == Site.kakuyomu ? 1 : 0);
      expect(find.text('更新後の作品名'), findsOneWidget);
      expect(find.text('短い新版'), findsOneWidget);
      expect(find.textContaining('作:新作者'), findsOneWidget);
      expect(find.text('完結'), findsOneWidget);
      expect(find.text('連載中'), findsNothing);
      expect(find.text('全2話'), findsOneWidget);
      expect(find.text('作品情報を更新しました'), findsOneWidget);

      expect(repository.episodeListCalls, 1);
      expect(identical(downloads.values.single, originalDownload), isTrue);
      expect(originalDownload.body, '元の本文');
      expect(originalDownload.sourceUpdatedAt, 'saved-revision');
      expect(original.title, '更新前の作品名');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('${site.name}: 作品Boxだけの変更でも書庫一覧が追従する', (tester) async {
      final original = createWork(site);
      await showScreen(tester, original, list: true);

      final latest = createWork(site, updated: true);
      repository.saved = latest;
      await tester.runAsync(() async {
        await works.put(latest.workId, latest);
      });
      await tester.pumpAndSettle();

      expect(find.text('更新後の作品名'), findsOneWidget);
      expect(find.text('短い新版'), findsOneWidget);
      expect(find.text('完結'), findsOneWidget);
      expect(find.text('更新前の作品名'), findsNothing);
      expect(downloads.length, 1);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('保留時は以前の情報を維持する', (tester) async {
    repository.handler = (_) async => false;
    await showScreen(tester, createWork(Site.narou));

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('更新前の作品名'), findsOneWidget);
    expect(find.text('連載中'), findsOneWidget);
    expect(find.text('作品情報が変更されたため更新を見送りました'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('失敗時は以前の情報を維持し再操作できる', (tester) async {
    repository.handler = (_) async => throw StateError('test refresh failure');
    await showScreen(tester, createWork(Site.narou));

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('更新前の作品名'), findsOneWidget);
    expect(find.text('作品情報を更新できませんでした'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('削除された作品の更新は呼び出さない', (tester) async {
    await showScreen(tester, createWork(Site.narou));
    repository.saved = null;

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(repository.narouCalls, 0);
    expect(find.text('更新対象の作品が登録されていません'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('更新中は重複実行を拒否する', (tester) async {
    final pending = Completer<bool>();
    repository.handler = (_) => pending.future;
    await showScreen(tester, createWork(Site.narou));

    final callback = tester.widget<IconButton>(button).onPressed!;
    callback();
    callback();
    await tester.pump();

    expect(repository.narouCalls, 1);
    expect(tester.widget<IconButton>(button).onPressed, isNull);

    repository.saved = createWork(Site.narou, updated: true);
    pending.complete(true);
    await tester.pumpAndSettle();

    expect(find.text('更新後の作品名'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('画面破棄後の遅延完了は画面を更新しない', (tester) async {
    final pending = Completer<bool>();
    repository.handler = (_) => pending.future;
    await showScreen(tester, createWork(Site.kakuyomu));

    await tester.tap(button);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    repository.saved = createWork(Site.kakuyomu, updated: true);
    pending.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
