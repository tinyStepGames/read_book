import 'package:html/dom.dart';

/// カクヨム検索結果カードの正式な連載状態です。
enum KakuyomuSerialStatus { unknown, ongoing, completed }

/// カクヨム検索結果カードの公式メタ情報です。
class KakuyomuSearchMetadataValue {
  final int episodeCount;
  final int characterCount;
  final int starCount;
  final KakuyomuSerialStatus serialStatus;

  const KakuyomuSearchMetadataValue({
    required this.episodeCount,
    required this.characterCount,
    required this.starCount,
    required this.serialStatus,
  });

  /// 話数と連載状態の両方を公式メタ情報から取得できたかを返します。
  bool get isReliable {
    return episodeCount > 0 && serialStatus != KakuyomuSerialStatus.unknown;
  }
}

/// カクヨム検索結果カードのメタ情報を解析します。
///
/// 紹介文、タイトル、キャッチコピー、レビュー本文などは判定対象にせず、
/// 公式の作品メタ情報欄だけを解析します。
abstract final class KakuyomuSearchMetadata {
  static final RegExp _episodeCountPattern = RegExp(
    r'^(連載中|完結済み?|完結)\s*(?:全\s*)?(\d[\d,]*)\s*話(?:\s|$)',
  );

  static final RegExp _characterCountPattern = RegExp(
    r'^(\d[\d,]*)\s*文字(?:\s|$)',
  );

  static final RegExp _starCountPattern = RegExp(r'^★\s*(\d[\d,]*)(?:\s|$)');

  /// 公式メタ情報欄から、話数・連載状態・文字数・★数を取得します。
  static KakuyomuSearchMetadataValue read(Element? container) {
    if (container == null) {
      return const KakuyomuSearchMetadataValue(
        episodeCount: 0,
        characterCount: 0,
        starCount: 0,
        serialStatus: KakuyomuSerialStatus.unknown,
      );
    }

    var episodeCount = 0;
    var characterCount = 0;
    var starCount = 0;
    var serialStatus = KakuyomuSerialStatus.unknown;

    for (final element in _metadataElements(container)) {
      final text = _cleanText(element.text);

      final episodeMatch = _episodeCountPattern.firstMatch(text);

      if (episodeMatch != null) {
        final parsedEpisodeCount = _parseNumber(episodeMatch.group(2));

        if (parsedEpisodeCount > 0) {
          episodeCount = parsedEpisodeCount;
        }

        serialStatus = switch (episodeMatch.group(1)) {
          '連載中' => KakuyomuSerialStatus.ongoing,
          '完結済' || '完結済み' || '完結' => KakuyomuSerialStatus.completed,
          _ => KakuyomuSerialStatus.unknown,
        };
      }

      final characterMatch = _characterCountPattern.firstMatch(text);

      if (characterMatch != null) {
        characterCount = _parseNumber(characterMatch.group(1));
      }

      final starMatch = _starCountPattern.firstMatch(text);

      if (starMatch != null) {
        starCount = _parseNumber(starMatch.group(1));
      }
    }

    return KakuyomuSearchMetadataValue(
      episodeCount: episodeCount,
      characterCount: characterCount,
      starCount: starCount,
      serialStatus: serialStatus,
    );
  }

  /// 既存の呼び出しとの互換性を維持するための話数取得です。
  static int episodeCount(Element? container) {
    return read(container).episodeCount;
  }

  static List<Element> _metadataElements(Element container) {
    return container.querySelectorAll(
      '[class*="WorkMetaBasicInformation"] li, '
      '[class*="Meta_metaItem"], '
      '.widget-workCard-meta li, '
      '.widget-workCard-metaItem, '
      '.widget-workCard-meta',
    );
  }

  static int _parseNumber(String? value) {
    return int.tryParse((value ?? '').replaceAll(',', '')) ?? 0;
  }

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
