import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/models/history_entry.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/screens/reader_screen.dart';
import 'package:read_book/services/app_session_service.dart';
import 'package:read_book/services/novel_repository.dart';

class _ReaderRepository extends NovelRepository {
  @override
  Future<void> saveWork(Work work) async {}

  @override
  Future<String> fetchEpisode({
    required Work work,
    required int episodeNo,
    required String episodeTitle,
  }) async {
    return List.generate(
      300,
      (index) => '本文の${index + 1}行目です。読書位置の保存と復元を確認します。',
    ).join('\n');
  }

  @override
  List<Map<String, String>> getDownloadedEpisodeList(String workId) {
    return [
      {'episodeNo': '1', 'title': '第1話'},
    ];
  }

  @override
  Future<List<Map<String, String>>> fetchEpisodeList(Work work) async {
    return getDownloadedEpisodeList(work.workId);
  }

  @override
  bool isDownloaded(Work work, int episodeNo) => true;
}

Work _createWork(Site site) {
  return Work(
    workId: site == Site.narou ? 'n3380le' : '2912051605992818100',
    siteIndex: site.index,
    title: '読書位置テスト',
    author: 'テスト作者',
    genre: '',
    summary: '',
    totalEpisodeCount: 1,
    checkedEpisodeCount: 1,
    lastUpdatedAt: DateTime.utc(2026, 1, 1),
    isCompleted: false,
  );
}

ScrollController _readerController(WidgetTester tester) {
  final scrollView = tester.widget<SingleChildScrollView>(
    find.byType(SingleChildScrollView),
  );
  return scrollView.controller!;
}

double _fraction(ScrollController controller) {
  final position = controller.position;
  return position.pixels / position.maxScrollExtent;
}

void main() {
  late Directory directory;
  late Box<HistoryEntry> history;
  late _ReaderRepository repository;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'reader_reading_position_test_',
    );
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(HistoryEntryAdapter());
    }
    history = await Hive.openBox<HistoryEntry>('history');
    await Hive.openBox<dynamic>(AppSessionService.boxName);
    repository = _ReaderRepository();
  });

  setUp(() async {
    history = await Hive.openBox<HistoryEntry>('history');
    await Hive.openBox<dynamic>(AppSessionService.boxName);
    await history.clear();
    await Hive.box<dynamic>(AppSessionService.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> finishHive(WidgetTester tester) async {
    // テストが作った非同期処理を進められる間にBoxを閉じます。
    // tearDownAllへ持ち越すと、元の仮想環境の処理を進められません。
    var finished = false;
    Object? closeError;
    final closing = Hive.close().then<void>(
      (_) {
        finished = true;
      },
      onError: (Object error, StackTrace stack) {
        closeError = error;
        finished = true;
      },
    );

    for (var attempt = 0; attempt < 200 && !finished; attempt++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
    }
    await tester.pump();

    expect(finished, isTrue, reason: '画面テスト内でHiveの終了処理が完了しませんでした。');
    await closing;
    expect(closeError, isNull, reason: 'Hiveの終了処理に失敗しました。');
  }

  Future<void> openReader(
    WidgetTester tester,
    Work work, {
    double? initialScrollFraction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          repository: repository,
          work: work,
          episodeNo: 1,
          episodeTitle: '第1話',
          initialScrollFraction: initialScrollFraction,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeReader(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    // flushを仮想非同期環境側で開始し、そこに属する保存処理も
    // pumpで進めながら、実ファイルI/Oの完了を待ちます。
    var flushFinished = false;
    Object? flushError;
    final flushFuture =
        Future.wait<void>([
          history.flush(),
          Hive.box<dynamic>(AppSessionService.boxName).flush(),
        ]).then<void>(
          (_) {
            flushFinished = true;
          },
          onError: (Object error, StackTrace stack) {
            flushError = error;
            flushFinished = true;
          },
        );

    for (var attempt = 0; attempt < 200 && !flushFinished; attempt++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
    }
    await tester.pump();

    expect(flushFinished, isTrue, reason: '画面終了後の履歴・セッション保存が完了しませんでした。');
    await flushFuture;
    expect(flushError, isNull, reason: '履歴・セッション保存でエラーが発生しました。');
  }

  for (final site in [Site.narou, Site.kakuyomu]) {
    testWidgets('${site.name}: 未指定の初期位置は同じ話の履歴から復元する', (tester) async {
      final work = _createWork(site);
      final key = '${work.workId}_1';
      await tester.runAsync(() async {
        await history.put(
          key,
          HistoryEntry(
            workId: work.workId,
            episodeNo: 1,
            scrollFraction: 0.45,
            lastReadAt: DateTime.utc(2026, 1, 1),
            episodeTitle: '第1話',
          ),
        );
      });

      await openReader(tester, work);

      final controller = _readerController(tester);
      expect(controller.position.maxScrollExtent, greaterThan(0));
      expect(_fraction(controller), closeTo(0.45, 0.01));
      expect(history.get(key)!.scrollFraction, closeTo(0.45, 0.01));
      expect(tester.takeException(), isNull);

      await closeReader(tester);
      await finishHive(tester);
    });

    testWidgets('${site.name}: 保存待ち中に閉じても位置を保存して開き直せる', (tester) async {
      final work = _createWork(site);
      final key = '${work.workId}_1';

      await openReader(tester, work);
      final controller = _readerController(tester);
      controller.jumpTo(controller.position.maxScrollExtent * 0.6);

      // 600msの保存タイマーを待たずに画面を閉じます。
      await closeReader(tester);
      expect(history.get(key)!.scrollFraction, closeTo(0.6, 0.01));

      await openReader(tester, work);
      expect(_fraction(_readerController(tester)), closeTo(0.6, 0.01));
      expect(tester.takeException(), isNull);

      await closeReader(tester);
      await finishHive(tester);
    });
  }

  testWidgets('初期位置が明示されている場合は履歴より優先する', (tester) async {
    final work = _createWork(Site.narou);
    final key = '${work.workId}_1';
    await tester.runAsync(() async {
      await history.put(
        key,
        HistoryEntry(
          workId: work.workId,
          episodeNo: 1,
          scrollFraction: 0.7,
          lastReadAt: DateTime.utc(2026, 1, 1),
        ),
      );
    });

    await openReader(tester, work, initialScrollFraction: 0.3);
    expect(_fraction(_readerController(tester)), closeTo(0.3, 0.01));
    await closeReader(tester);

    // 明示的な0は「履歴から復元」ではなく「先頭から」です。
    await openReader(tester, work, initialScrollFraction: 0);
    expect(_readerController(tester).offset, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
    await closeReader(tester);
    await finishHive(tester);
  });
}
