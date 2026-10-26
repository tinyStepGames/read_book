import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/services/narou_api_client.dart';
import 'package:read_book/widgets/expandable_work_card.dart';

void main() {
  testWidgets('検索カードは取得済みの短い概要を即時表示する', (tester) async {
    const shortSummary = '検索結果に含まれている短い紹介文です。';

    const work = NarouSearchResult(
      title: 'テスト作品',
      ncode: '2912051600000000000',
      authorId: 'test-author',
      author: 'テスト作者',
      summary: shortSummary,
      biggenre: 2,
      genre: 2,
      keyword: 'テスト',
      generalFirstup: '',
      generalLastup: '2026-10-26',
      end: 1,
      length: 1000,
      favNovelCnt: 10,
      generalAllNo: 1,
      novelType: 1,
      site: Site.kakuyomu,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableWorkCard(
            work: work,
            favoriteColor: null,
            onFavoriteChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text(shortSummary), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.textContaining('テスト作品'));
    await tester.pump();

    expect(find.text(shortSummary), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
