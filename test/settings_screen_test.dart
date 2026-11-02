import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:read_book/screens/settings_screen.dart';
import 'package:read_book/services/app_session_service.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'read_book_settings_screen_test_',
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

  testWidgets('設定画面に作者ブロックとバックアップ項目を表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('ブロック中の作者'), findsOneWidget);
    expect(find.text('ブロック中の作者はいません'), findsOneWidget);
    expect(find.text('バックアップを作成'), findsOneWidget);
    expect(find.text('バックアップから復元'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
