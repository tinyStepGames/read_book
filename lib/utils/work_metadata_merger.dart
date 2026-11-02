import '../models/work.dart';

/// 検索結果から作られた作品情報を、保存済み情報へ安全に統合します。
abstract final class WorkMetadataMerger {
  static Work mergeSearchResult({
    required Work incoming,
    required Work? existing,
  }) {
    if (existing == null) {
      return incoming;
    }

    return Work(
      workId: incoming.workId,
      siteIndex: incoming.siteIndex,
      title: _preferNonEmpty(incoming.title, existing.title),
      author: _preferNonEmpty(incoming.author, existing.author),
      genre: _preferNonEmpty(incoming.genre, existing.genre),

      // 詳細画面で取得した正式な長いあらすじを、
      // 検索結果の短い概要で上書きしません。
      summary: _preferLonger(incoming.summary, existing.summary),

      // 一時的な解析失敗、非公開化、サイト側の欠落によって、
      // 保存済み話数を減らしません。
      totalEpisodeCount: _maximumPositive(
        incoming.totalEpisodeCount,
        existing.totalEpisodeCount,
      ),
      checkedEpisodeCount: _maximumPositive(
        incoming.checkedEpisodeCount,
        existing.checkedEpisodeCount,
      ),

      // 不正な現在時刻などで更新日時を巻き戻さないよう、
      // より新しい日時を維持します。
      lastUpdatedAt: incoming.lastUpdatedAt.isAfter(existing.lastUpdatedAt)
          ? incoming.lastUpdatedAt
          : existing.lastUpdatedAt,

      // 呼び出し側は信頼できる公式メタ情報またはAPI応答だけを渡します。
      // そのため完結から連載中への修復も許可します。
      isCompleted: incoming.isCompleted,

      // 読書開始日時は検索結果で上書きしません。
      firstOpenedAt: existing.firstOpenedAt ?? incoming.firstOpenedAt,

      authorId: _preferNullableNonEmpty(incoming.authorId, existing.authorId),
      keyword: _preferNullableNonEmpty(incoming.keyword, existing.keyword),
    );
  }

  static String _preferNonEmpty(String incoming, String existing) {
    final normalizedIncoming = incoming.trim();

    if (normalizedIncoming.isEmpty) {
      return existing;
    }

    return incoming;
  }

  static String? _preferNullableNonEmpty(String? incoming, String? existing) {
    final normalizedIncoming = incoming?.trim() ?? '';

    if (normalizedIncoming.isEmpty) {
      return existing;
    }

    return incoming;
  }

  static String _preferLonger(String incoming, String existing) {
    final normalizedIncoming = incoming.trim();
    final normalizedExisting = existing.trim();

    if (normalizedIncoming.isEmpty) {
      return existing;
    }

    if (normalizedExisting.isEmpty) {
      return incoming;
    }

    return normalizedIncoming.length >= normalizedExisting.length
        ? incoming
        : existing;
  }

  static int _maximumPositive(int incoming, int existing) {
    if (incoming <= 0) {
      return existing;
    }

    if (existing <= 0) {
      return incoming;
    }

    return incoming >= existing ? incoming : existing;
  }
}
