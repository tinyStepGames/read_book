/// カクヨムの作者作品一覧へ安全にアクセスするためのURL生成処理です。
abstract final class KakuyomuAuthorSearch {
  static final RegExp _safeAuthorIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  /// 作者IDを検証し、前後の空白を除いた値を返します。
  static String normalizeAuthorId(String authorId) {
    final normalized = authorId.trim();

    if (normalized.isEmpty || !_safeAuthorIdPattern.hasMatch(normalized)) {
      throw const FormatException('カクヨムの作者IDが不正です');
    }

    return normalized;
  }

  /// 作者が投稿した作品一覧ページのURLを返します。
  static Uri buildWorksUri({required String authorId, int page = 1}) {
    final normalizedAuthorId = normalizeAuthorId(authorId);
    final normalizedPage = page < 1 ? 1 : page;

    return Uri.https(
      'kakuyomu.jp',
      '/users/$normalizedAuthorId/works',
      <String, String>{if (normalizedPage > 1) 'page': '$normalizedPage'},
    );
  }
}
