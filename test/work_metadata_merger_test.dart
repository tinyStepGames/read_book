import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/models/work.dart';
import 'package:read_book/utils/work_metadata_merger.dart';

void main() {
  Work createWork({
    String title = '作品名',
    String author = '作者',
    String genre = 'ファンタジー',
    String summary = '概要',
    int totalEpisodeCount = 10,
    int checkedEpisodeCount = 10,
    DateTime? lastUpdatedAt,
    bool isCompleted = false,
    DateTime? firstOpenedAt,
    String? authorId = 'author-id',
    String? keyword = 'タグ',
  }) {
    return Work(
      workId: 'work-id',
      siteIndex: Site.kakuyomu.index,
      title: title,
      author: author,
      genre: genre,
      summary: summary,
      totalEpisodeCount: totalEpisodeCount,
      checkedEpisodeCount: checkedEpisodeCount,
      lastUpdatedAt: lastUpdatedAt ?? DateTime.utc(2026, 1, 1),
      isCompleted: isCompleted,
      firstOpenedAt: firstOpenedAt,
      authorId: authorId,
      keyword: keyword,
    );
  }

  group('WorkMetadataMerger', () {
    test('既存作品がなければ検索結果をそのまま返す', () {
      final incoming = createWork();

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: null,
      );

      expect(identical(merged, incoming), isTrue);
    });

    test('一時的な0話判定で保存済み話数を減らさない', () {
      final existing = createWork(
        totalEpisodeCount: 71,
        checkedEpisodeCount: 71,
      );
      final incoming = createWork(totalEpisodeCount: 0, checkedEpisodeCount: 0);

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.totalEpisodeCount, 71);
      expect(merged.checkedEpisodeCount, 71);
    });

    test('取得話数が減少しても保存済み話数を維持する', () {
      final existing = createWork(
        totalEpisodeCount: 71,
        checkedEpisodeCount: 71,
      );
      final incoming = createWork(
        totalEpisodeCount: 70,
        checkedEpisodeCount: 70,
      );

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.totalEpisodeCount, 71);
      expect(merged.checkedEpisodeCount, 71);
    });

    test('取得話数が増加した場合は新しい話数を使用する', () {
      final existing = createWork(
        totalEpisodeCount: 71,
        checkedEpisodeCount: 71,
      );
      final incoming = createWork(
        totalEpisodeCount: 72,
        checkedEpisodeCount: 72,
      );

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.totalEpisodeCount, 72);
      expect(merged.checkedEpisodeCount, 72);
    });

    test('空の作者やジャンルやタグで既存情報を消さない', () {
      final existing = createWork(
        author: '保存済み作者',
        genre: '保存済みジャンル',
        authorId: 'saved-author',
        keyword: '保存済みタグ',
      );
      final incoming = createWork(
        author: ' ',
        genre: '',
        authorId: '',
        keyword: null,
      );

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.author, '保存済み作者');
      expect(merged.genre, '保存済みジャンル');
      expect(merged.authorId, 'saved-author');
      expect(merged.keyword, '保存済みタグ');
    });

    test('長い正式なあらすじを短い検索概要で上書きしない', () {
      final existing = createWork(summary: 'これは詳細画面から取得した十分に長い正式なあらすじです。');
      final incoming = createWork(summary: '短い概要');

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.summary, 'これは詳細画面から取得した十分に長い正式なあらすじです。');
    });

    test('信頼できる状態で完結から連載中へ修復する', () {
      final existing = createWork(isCompleted: true);
      final incoming = createWork(isCompleted: false);

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.isCompleted, isFalse);
    });

    test('読書開始日時を検索結果で上書きしない', () {
      final openedAt = DateTime.utc(2026, 1, 2);
      final existing = createWork(firstOpenedAt: openedAt);
      final incoming = createWork(firstOpenedAt: null);

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.firstOpenedAt, openedAt);
    });

    test('更新日時を古い値へ巻き戻さない', () {
      final existing = createWork(lastUpdatedAt: DateTime.utc(2026, 2, 1));
      final incoming = createWork(lastUpdatedAt: DateTime.utc(2026, 1, 1));

      final merged = WorkMetadataMerger.mergeSearchResult(
        incoming: incoming,
        existing: existing,
      );

      expect(merged.lastUpdatedAt, DateTime.utc(2026, 2, 1));
    });
  });
}
