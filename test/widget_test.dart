import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/main.dart';
import 'package:read_book/models/download.dart';
import 'package:read_book/models/download_job.dart';
import 'package:read_book/models/episode.dart';
import 'package:read_book/models/favorite.dart';
import 'package:read_book/models/history_entry.dart';
import 'package:read_book/models/read_mark.dart';
import 'package:read_book/models/saved_search.dart';
import 'package:read_book/models/work.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_widget_test_',
    );

    Hive.init(temporaryDirectory.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WorkAdapter());
    }

    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(EpisodeAdapter());
    }

    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(FavoriteAdapter());
    }

    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(SavedSearchAdapter());
    }

    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(HistoryEntryAdapter());
    }

    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(DownloadJobAdapter());
    }

    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(DownloadAdapter());
    }

    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(ReadMarkAdapter());
    }

    await Hive.openBox<Work>('works');
    await Hive.openBox<Episode>('episodes');
    await Hive.openBox<Favorite>('favorites');
    await Hive.openBox<SavedSearch>('saved_searches');
    await Hive.openBox<HistoryEntry>('history');
    await Hive.openBox<DownloadJob>('download_jobs');
    await Hive.openBox<Download>('downloads');
    await Hive.openBox<ReadMark>('read_marks');
    await Hive.openBox<dynamic>('app_state');
  });

  tearDownAll(() async {
    await Hive.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // SearchScreenの初期検索とDio内部の非同期処理を完了させます。
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // テスト終了前にアプリのWidgetツリーを明示的に破棄します。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
