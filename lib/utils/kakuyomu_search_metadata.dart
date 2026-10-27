import 'package:html/dom.dart';

/// カクヨム検索結果カードのメタ情報を解析します。
abstract final class KakuyomuSearchMetadata {
  static final RegExp _episodeCountPattern = RegExp(
    r'(?:連載中|完結済み?|完結)\s*(?:全\s*)?(\d[\d,]*)\s*話',
  );

  /// 紹介文やタイトルに含まれる「1話」などを無視し、
  /// 作品メタ情報欄に表示された正式な話数だけを返します。
  static int episodeCount(Element? container) {
    if (container == null) {
      return 0;
    }

    final metadataElements = container.querySelectorAll(
      '[class*="WorkMetaBasicInformation"] li, '
      '[class*="Meta_metaItem"], '
      '.widget-workCard-meta li, '
      '.widget-workCard-metaItem, '
      '.widget-workCard-meta',
    );

    for (final element in metadataElements) {
      final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final match = _episodeCountPattern.firstMatch(text);

      if (match == null) {
        continue;
      }

      final value = match.group(1)?.replaceAll(',', '') ?? '';
      final parsed = int.tryParse(value);

      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    // 正式なメタ情報を特定できない場合は、
    // 紹介文などの数字を誤認しないよう0を返します。
    return 0;
  }
}
