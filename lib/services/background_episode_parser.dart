import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/site.dart';
import '../utils/novel_body_codec.dart';

class BackgroundEpisodeParser {
  const BackgroundEpisodeParser._();

  static String parse({required Site site, required String html}) {
    if (html.trim().isEmpty) {
      throw StateError('ダウンロードした本文ページが空です');
    }

    return switch (site) {
      Site.narou => _parseNarou(html),
      Site.kakuyomu => _parseKakuyomu(html),
    };
  }

  static String _parseNarou(String html) {
    final document = html_parser.parse(html);

    final bodyElement =
        document.querySelector('.p-novel__body') ??
        document.querySelector('#novel_honbun');

    if (bodyElement == null || bodyElement.text.trim().isEmpty) {
      throw StateError('なろうの本文要素を取得できませんでした');
    }

    return _encodeNarouBody(bodyElement);
  }

  static String _encodeNarouBody(Element bodyElement) {
    Element? prefaceElement;
    Element? mainElement;
    Element? afterwordElement;

    for (final element in bodyElement.querySelectorAll('.p-novel__text')) {
      if (element.classes.contains('p-novel__text--preface')) {
        prefaceElement ??= element;
      } else if (element.classes.contains('p-novel__text--afterword')) {
        afterwordElement ??= element;
      } else {
        mainElement ??= element;
      }
    }

    if (prefaceElement == null &&
        mainElement == null &&
        afterwordElement == null) {
      return NovelBodyCodec.encodeElement(bodyElement);
    }

    final hasPreface =
        prefaceElement != null && prefaceElement.text.trim().isNotEmpty;
    final hasAfterword =
        afterwordElement != null && afterwordElement.text.trim().isNotEmpty;
    final showMainLabel = hasPreface || hasAfterword;
    final sections = <String>[];

    void addSection({
      required String label,
      required Element? element,
      required bool showLabel,
    }) {
      if (element == null || element.text.trim().isEmpty) {
        return;
      }

      final encoded = NovelBodyCodec.encodeElement(element);
      final payload = NovelBodyCodec.payloadOf(
        encoded,
      ).replaceFirst(RegExp(r'\n+$'), '');

      if (payload.trim().isEmpty) {
        return;
      }

      sections.add(
        showLabel ? '<strong>【$label】</strong>\n\n$payload' : payload,
      );
    }

    addSection(label: '前書き', element: prefaceElement, showLabel: true);
    addSection(label: '本文', element: mainElement, showLabel: showMainLabel);
    addSection(label: 'あとがき', element: afterwordElement, showLabel: true);

    if (sections.isEmpty) {
      return NovelBodyCodec.encodeElement(bodyElement);
    }

    return '${NovelBodyCodec.prefix}'
        '${sections.join('\n\n<hr>\n\n')}';
  }

  static String _parseKakuyomu(String html) {
    final document = html_parser.parse(html);

    final bodyElement =
        document.querySelector('.widget-episodeBody') ??
        document.querySelector('.js-episode-body') ??
        document.querySelector('[class*="episodeBody"]');

    if (bodyElement == null || bodyElement.text.trim().isEmpty) {
      throw StateError('カクヨムの本文要素を取得できませんでした');
    }

    return NovelBodyCodec.encodeElement(bodyElement);
  }
}
