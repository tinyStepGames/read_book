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
import 'package:read_book/services/novel_repository.dart';

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
    final value = saved;
    return value?.workId == workId ? value : null;
  }

  @override
  Future<void> refreshWorkDetails(Work work) async {}

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(Work work) async {
    episodeListCalls++;
    return [
      {'episodeNo': '1', 'title': '既存の第1話'},
    ];
  }

  @override
  Future<void> updateDownloadPublishedDates({
    required Work work,
    required List<Map<String, String>> episodeList,
  }) async {}

  @override
  bool hasAnyDownload(String workId) => false;

  @override
  bool isDownloaded(Work work, int episodeNo) => false;

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
  group('作品詳細画面の作品情報更新', () {
    late Directory directory;
    late _Repository repository;

    final button = find.byKey(const ValueKey('refresh-work-information'));

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp(
        'work_detail_work_information_refresh_test_',
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
      repository.narouCalls = 0;
      repository.kakuyomuCalls = 0;
      repository.episodeListCalls = 0;
      repository.handler = (work) async {
        repository.saved = createWork(
          Site.values[work.siteIndex],
          updated: true,
        );
        return true;
      };
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    Future<void> showScreen(WidgetTester tester, Work work) async {
      repository.saved = work;
      await tester.pumpWidget(
        MaterialApp(
          home: WorkDetailScreen(repository: repository, work: work),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final site in [Site.narou, Site.kakuyomu]) {
      testWidgets('${site.name}の更新後情報を画面へ反映する', (tester) async {
        final original = createWork(site);
        await showScreen(tester, original);

        expect(repository.narouCalls, 0);
        expect(repository.kakuyomuCalls, 0);

        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(repository.narouCalls, site == Site.narou ? 1 : 0);
        expect(repository.kakuyomuCalls, site == Site.kakuyomu ? 1 : 0);
        expect(find.text('更新後の作品名'), findsOneWidget);
        expect(find.text('短い新版'), findsOneWidget);
        expect(find.textContaining('作:新作者'), findsOneWidget);
        expect(find.text('全2話'), findsOneWidget);
        expect(find.text('完結'), findsOneWidget);
        expect(find.text('作品情報を更新しました'), findsOneWidget);

        // 作品情報の更新では目次を再取得しません。
        expect(repository.episodeListCalls, 1);
        expect(find.text('既存の第1話'), findsOneWidget);
        expect(original.title, '更新前の作品名');
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('保留を成功扱いせず以前の表示を維持する', (tester) async {
      repository.handler = (_) async => false;
      await showScreen(tester, createWork(Site.narou));

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('更新前の作品名'), findsOneWidget);
      expect(find.text('作品情報が変更されたため更新を見送りました'), findsOneWidget);
      expect(find.text('作品情報を更新しました'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('通信失敗を通知しボタンを再び有効にする', (tester) async {
      repository.handler = (_) async =>
          throw StateError('test refresh failure');
      await showScreen(tester, createWork(Site.narou));

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('更新前の作品名'), findsOneWidget);
      expect(find.text('作品情報を更新できませんでした'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('登録から削除された作品は更新処理を呼ばない', (tester) async {
      await showScreen(tester, createWork(Site.narou));
      repository.saved = null;

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(repository.narouCalls, 0);
      expect(find.text('更新対象の作品が登録されていません'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('更新中の重複実行を拒否する', (tester) async {
      final pending = Completer<bool>();
      repository.handler = (_) => pending.future;
      await showScreen(tester, createWork(Site.narou));

      final callback = tester.widget<OutlinedButton>(button).onPressed!;
      callback();
      callback();
      await tester.pump();

      expect(repository.narouCalls, 1);
      expect(find.text('作品情報を更新中…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

      repository.saved = createWork(Site.narou, updated: true);
      pending.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('更新後の作品名'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('取得中に画面を閉じても破棄済み画面を更新しない', (tester) async {
      final pending = Completer<bool>();
      repository.handler = (_) => pending.future;
      await showScreen(tester, createWork(Site.kakuyomu));

      await tester.tap(button);
      await tester.pump();
      expect(repository.kakuyomuCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      repository.saved = createWork(Site.kakuyomu, updated: true);
      pending.complete(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }, skip: Platform.isIOS);
}
