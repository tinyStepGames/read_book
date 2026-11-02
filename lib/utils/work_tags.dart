/// 作品タグの保存・復元処理です.
///
/// 既存の小説家になろう・カクヨムデータは空白区切りで読み込み、
/// 新しく取得するカクヨムデータは区切り文字を使ってタグ内の空白を保持します。
abstract final class WorkTags {
  static const String separator = '\u001f';

  static String encode(Iterable<String> tags) {
    return tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .join(separator);
  }

  static List<String> decode(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return const <String>[];
    }

    final values = normalized.contains(separator)
        ? normalized.split(separator)
        : normalized.split(RegExp(r'[\s　]+'));

    return values
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}
