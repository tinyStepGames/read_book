import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/services/narou_api_client.dart';
import 'package:read_book/widgets/expandable_work_card.dart';

void main() {
  NarouSearchResult createWork({required Site site, int favoriteCount = 10}) {
    return NarouSearchResult(
      title: 'テスト作品',
      ncode: site == Site.kakuyomu ? '2912051600000000000' : 'N0001AA',
      authorId: 'test-author',
      author: 'テスト作者',
      summary: '検索結果に含まれている短い紹介文です。',
      biggenre: 2,
      genre: 2,
      keyword: 'テスト',
      generalFirstup: '',
      generalLastup: '2026-10-26',
      end: 1,
      length: 1000,
      favNovelCnt: favoriteCount,
      generalAllNo: 1,
      novelType: 1,
      site: site,
    );
  }

  Widget buildCard(NarouSearchResult work) {
    return MaterialApp(
      home: Scaffold(
        body: ExpandableWorkCard(
          work: work,
          favoriteColor: null,
          onFavoriteChanged: (_) {},
        ),
      ),
    );
  }

  testWidgets('検索カードは取得済みの短い概要を即時表示する', (tester) async {
    final work = createWork(site: Site.kakuyomu);
    const shortSummary = '検索結果に含まれている短い紹介文です。';

    await tester.pumpWidget(buildCard(work));

    expect(find.text(shortSummary), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.textContaining('テスト作品'));
    await tester.pump();

    expect(find.text(shortSummary), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('カクヨムでは評価値を星記号付きで表示する', (tester) async {
    final work = createWork(site: Site.kakuyomu, favoriteCount: 135);

    await tester.pumpWidget(buildCard(work));
    await tester.tap(find.textContaining('テスト作品'));
    await tester.pump();

    expect(find.text('★135'), findsOneWidget);
    expect(find.text('お気に入り人数:135'), findsNothing);
  });

  testWidgets('小説家になろうではお気に入り人数として表示する', (tester) async {
    final work = createWork(site: Site.narou, favoriteCount: 246);

    await tester.pumpWidget(buildCard(work));
    await tester.tap(find.textContaining('テスト作品'));
    await tester.pump();

    expect(find.text('お気に入り人数:246'), findsOneWidget);
    expect(find.text('★246'), findsNothing);
  });
}
