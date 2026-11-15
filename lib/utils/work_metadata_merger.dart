import '../models/work.dart';

/// 検索結果から作られた作品情報を、保存済み情報へ安全に統合します。
abstract final class WorkMetadataMerger {
  /// 正式な作品詳細を、端末側の確認状態を維持して統合します。
  ///
  /// 呼び出し側は、同じ作品について取得した正式な詳細情報を渡します。
  /// 未取得の文字列は空文字またはnullで表し、既存値を維持します。
  /// 空のあらすじ・タグによる明示的な削除には対応しません。
  /// 入力は変更せず、未保存の新しいWorkを返します。
  static Work mergeRefreshedDetails({
    required Work incoming,
    required Work existing,
  }) {
    if (existing.workId.trim().isEmpty ||
        incoming.workId.trim().isEmpty ||
        incoming.workId != existing.workId ||
        incoming.siteIndex != existing.siteIndex) {
      throw ArgumentError('更新する作品のIDまたはサイトが一致しません。');
    }

    return Work(
      workId: existing.workId,
      siteIndex: existing.siteIndex,
      title: _preferNonEmpty(incoming.title, existing.title),
      author: _preferNonEmpty(incoming.author, existing.author),
      genre: _preferNonEmpty(incoming.genre, existing.genre),
      // 検索結果とは異なり、短く修正された正式なあらすじも反映します。
      summary: _preferNonEmpty(incoming.summary, existing.summary),
      totalEpisodeCount: _maximumPositive(
        incoming.totalEpisodeCount,
        existing.totalEpisodeCount,
      ),
      // 作品情報の取得を「読者が新着を確認した」扱いにはしません。
      checkedEpisodeCount: existing.checkedEpisodeCount,
      lastUpdatedAt: incoming.lastUpdatedAt.isAfter(existing.lastUpdatedAt)
          ? incoming.lastUpdatedAt
          : existing.lastUpdatedAt,
      isCompleted: incoming.isCompleted,
      firstOpenedAt: existing.firstOpenedAt,
      authorId: _preferNullableNonEmpty(incoming.authorId, existing.authorId),
      keyword: _preferNullableNonEmpty(incoming.keyword, existing.keyword),
    );
  }

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
