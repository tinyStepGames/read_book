import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/services/app_session_service.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_app_session_test_',
    );

    Hive.init(temporaryDirectory.path);
    await Hive.openBox<dynamic>(AppSessionService.boxName);
  });

  tearDown(() async {
    await Hive.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('選択したタブを保存して復元できる', () async {
    await AppSessionService.saveSelectedTab(3);

    expect(AppSessionService.selectedTab, 3);
  });

  test('Readerの状態を保存して復元できる', () async {
    await AppSessionService.saveReader(
      workId: 'N1234AB',
      episodeNo: 12,
      episodeTitle: '第十二話',
      scrollFraction: 0.42,
      fontSize: 19,
    );

    final session = AppSessionService.readerSession;

    expect(session, isNotNull);
    expect(session!.workId, 'N1234AB');
    expect(session.episodeNo, 12);
    expect(session.episodeTitle, '第十二話');
    expect(session.scrollFraction, 0.42);
    expect(session.fontSize, 19);
  });

  test('Readerを閉じると復元対象から外れる', () async {
    await AppSessionService.saveReader(
      workId: 'N1234AB',
      episodeNo: 1,
      episodeTitle: '第一話',
      scrollFraction: 0.5,
      fontSize: 16,
    );

    await AppSessionService.clearReader();

    expect(AppSessionService.readerSession, isNull);
  });

  test('範囲外のタブと表示設定を安全な範囲へ補正する', () async {
    await AppSessionService.saveSelectedTab(99);

    await AppSessionService.saveReader(
      workId: 'N1234AB',
      episodeNo: 1,
      episodeTitle: '第一話',
      scrollFraction: 2,
      fontSize: 100,
    );

    final session = AppSessionService.readerSession;

    expect(AppSessionService.selectedTab, 3);
    expect(session!.scrollFraction, 1);
    expect(session.fontSize, 32);
  });
}
