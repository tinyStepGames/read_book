import 'package:html/dom.dart';

/// カクヨム検索結果に表示される短い作品説明を抽出します。
///
/// 右側の色線とともに表示されるキャッチコピーや読者コメントではなく、
/// 作品タイトル直下にある説明文を優先します。
abstract final class KakuyomuSearchSummary {
  static String extract({required Element? container, required String workId}) {
    if (container == null || workId.trim().isEmpty) {
      return '';
    }

    final expectedHref = '/works/${workId.trim()}';

    // 以前の検索ページで使用されていた説明要素を先に確認します。
    final legacyIntroduction = container.querySelector(
      '.widget-workCard-introduction',
    );
    final legacyText = _cleanText(legacyIntroduction?.text ?? '');

    if (legacyText.isNotEmpty) {
      return legacyText;
    }

    // 現在の検索ページでは、作品リンクの中にあるWeakTextが
    // タイトル直下の短い説明です。
    //
    // EyeCatch_catchphraseはWeakTextの中にないため、
    // 右側のキャッチコピーや読者コメントは取得しません。
    final workAnchors = container.querySelectorAll('a[href^="/works/"]');

    for (final anchor in workAnchors) {
      if (anchor.attributes['href'] != expectedHref) {
        continue;
      }

      final description = anchor.querySelector('[class*="WeakText_weakText"]');

      final text = _cleanText(description?.text ?? '');

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
