import '../utils/kakuyomu_author_search.dart';
import '../utils/work_tags.dart';

/// 作品情報更新用に検証したカクヨムAPIの応答です。
///
/// Hiveへの保存や通信は行いません。
/// 省略可能な文字列の空値は、統合時に既存値を維持するために使います。
class KakuyomuWorkMetadata {
  const KakuyomuWorkMetadata._({
    required this.workId,
    required this.title,
    required this.author,
    required this.summary,
    required this.genre,
    required this.episodeCount,
    required this.isCompleted,
    required this.authorId,
    required this.keyword,
  });

  final String workId;
  final String title;
  final String author;
  final String summary;
  final String genre;
  final int episodeCount;
  final bool isCompleted;
  final String? authorId;
  final String keyword;

  factory KakuyomuWorkMetadata.fromJson(
    Map<String, dynamic> json, {
    required String expectedWorkId,
  }) {
    final idPattern = RegExp(r'^[1-9][0-9]*$');
    final id = json['id'];

    if (!idPattern.hasMatch(expectedWorkId) ||
        id is! String ||
        id != expectedWorkId) {
      throw const FormatException('カクヨムの作品IDが一致しません。');
    }

    final title = _requiredText(json['title']);
    final authorData = _object(json['author']);
    final alternateAuthor = _optionalText(json['alternate_author_name']);
    final activityName = _optionalText(authorData['activity_name']);
    final author = alternateAuthor.isNotEmpty ? alternateAuthor : activityName;

    if (author.isEmpty) {
      throw const FormatException('カクヨムの作者名を取得できませんでした。');
    }

    // 正式なあらすじは空文字も許可します。
    // 欠落や型違いを「空の正式なあらすじ」とは扱いません。
    final introduction = json['introduction'];
    if (introduction is! String) {
      throw const FormatException('カクヨムのあらすじの形式が不正です。');
    }

    final count = json['public_episode_count'];
    final completed = json['is_completed'];
    if (count is! int || count <= 0 || completed is! bool) {
      throw const FormatException('カクヨムの公開話数または完結状態が不正です。');
    }

    var genre = '';
    if (json['genre'] != null) {
      genre = _optionalText(_object(json['genre'])['label']);
    }

    String? authorId;
    final permalink = _optionalText(authorData['permalink']);
    if (permalink.isNotEmpty) {
      final uri = Uri.tryParse(permalink);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'kakuyomu.jp' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.pathSegments.length != 2 ||
          uri.pathSegments.first != 'users') {
        throw const FormatException('カクヨムの作者ページURLが不正です。');
      }
      authorId = KakuyomuAuthorSearch.normalizeAuthorId(uri.pathSegments[1]);
    }

    final tags = <String>[];
    final rawTags = json['tags'];
    if (rawTags != null) {
      if (rawTags is! List) {
        throw const FormatException('カクヨムのタグの形式が不正です。');
      }
      for (final rawTag in rawTags) {
        final label = _requiredText(_object(rawTag)['label']);
        if (label.contains(WorkTags.separator)) {
          throw const FormatException('カクヨムのタグに保存用の区切り文字があります。');
        }
        if (!tags.contains(label)) {
          tags.add(label);
        }
      }
    }

    return KakuyomuWorkMetadata._(
      workId: id,
      title: title,
      author: author,
      summary: introduction
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .trim(),
      genre: genre,
      episodeCount: count,
      isCompleted: completed,
      authorId: authorId,
      keyword: WorkTags.encode(tags),
    );
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('カクヨムの作品情報の形式が不正です。');
    }
    return value;
  }

  static String _requiredText(Object? value) {
    final text = _optionalText(value);
    if (text.isEmpty) {
      throw const FormatException('カクヨムの作品情報に必須の文字列がありません。');
    }
    return text;
  }

  static String _optionalText(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is! String) {
      throw const FormatException('カクヨムの作品情報の文字列形式が不正です。');
    }
    return value.trim();
  }
}
