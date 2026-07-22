import 'dart:convert';

import 'package:html/dom.dart' as dom;

/// 小説本文のHTMLから、安全な装飾だけを残す変換器です。
///
/// 保存文字列の先頭に識別子を付けるため、以前のプレーンテキスト本文とも
/// 共存できます。
class NovelBodyCodec {
  NovelBodyCodec._();

  static const String prefix = '@@READ_BOOK_RICH_V1@@\n';

  /// 装飾付き本文かどうかを判定します。
  static bool isRichBody(String body) => body.startsWith(prefix);

  /// 保存用本文から装飾部分を取り出します。
  static String payloadOf(String body) {
    if (!isRichBody(body)) {
      return body;
    }

    return body.substring(prefix.length);
  }

  /// サイトの本文要素を、アプリ用の安全なHTMLへ変換します。
  static String encodeElement(dom.Element bodyElement) {
    final encoded = _encodeNodes(
      bodyElement.nodes,
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 本文末尾に増えた改行だけを整理します。
    // 行頭スペースや本文中の空行は削除しません。
    final normalized = encoded
        // HTML整形などによって3つ以上連続した改行は、
        // 1行分の空行を表す2改行までに制限します。
        .replaceAll(RegExp(r'\n[ \t]*\n(?:[ \t]*\n)+'), '\n\n')
        .replaceFirst(RegExp(r'\n+$'), '');

    return '$prefix$normalized';
  }

  static String _encodeNodes(List<dom.Node> nodes) {
    return nodes.map(_encodeNode).join();
  }

  static String _encodeNode(dom.Node node) {
    if (node is dom.Text) {
      final text = node.data;

      // HTMLソースを整形するためだけに入っている改行・インデントは
      // 小説本文の改行として保存しません。
      if (text.trim().isEmpty && (text.contains('\n') || text.contains('\r'))) {
        return '';
      }

      return const HtmlEscape(HtmlEscapeMode.element).convert(text);
    }

    if (node is! dom.Element) {
      return '';
    }

    final tag = (node.localName ?? '').toLowerCase();

    switch (tag) {
      case 'ruby':
        return _encodeRuby(node);

      case 'rt':
      case 'rp':
        // ruby要素の処理時にまとめて扱います。
        return '';

      case 'em':
        if (node.classes.contains('emphasisDots') ||
            node.attributes['data-novel-emphasis'] == 'dot') {
          final text = node.text;
          final escaped = const HtmlEscape(
            HtmlEscapeMode.element,
          ).convert(text);

          return '<em data-novel-emphasis="dot">$escaped</em>';
        }

        return '<em>${_encodeNodes(node.nodes)}</em>';

      case 'strong':
      case 'b':
        return '<strong>${_encodeNodes(node.nodes)}</strong>';

      case 'i':
        return '<i>${_encodeNodes(node.nodes)}</i>';

      case 'u':
        return '<u>${_encodeNodes(node.nodes)}</u>';

      case 's':
      case 'strike':
      case 'del':
        return '<s>${_encodeNodes(node.nodes)}</s>';

      case 'br':
        return '\n';

      case 'hr':
        return '\n<hr>\n';

      case 'p':
      case 'div':
      case 'section':
      case 'article':
      case 'blockquote':
        return '${_encodeNodes(node.nodes)}\n';

      case 'img':
        final alt = node.attributes['alt']?.trim() ?? '';

        if (alt.isEmpty) {
          return '';
        }

        final escapedAlt = const HtmlEscape(
          HtmlEscapeMode.element,
        ).convert(alt);

        return '[画像: $escapedAlt]';

      case 'script':
      case 'style':
      case 'noscript':
      case 'iframe':
      case 'button':
        return '';

      default:
        // 未知のタグは装飾だけを外し、中の文章は残します。
        return _encodeNodes(node.nodes);
    }
  }

  static String _encodeRuby(dom.Element rubyElement) {
    final baseBuffer = StringBuffer();
    String rubyText = '';

    for (final child in rubyElement.nodes) {
      if (child is dom.Element) {
        final childTag = (child.localName ?? '').toLowerCase();

        if (childTag == 'rt') {
          rubyText += child.text;
          continue;
        }

        if (childTag == 'rp') {
          continue;
        }
      }

      baseBuffer.write(child.text);
    }

    final baseText = baseBuffer.toString();
    final normalizedRuby = rubyText.trim();

    if (baseText.isEmpty) {
      return '';
    }

    final escapedBase = const HtmlEscape(
      HtmlEscapeMode.element,
    ).convert(baseText);

    if (normalizedRuby.isEmpty) {
      return escapedBase;
    }

    final escapedRuby = const HtmlEscape(
      HtmlEscapeMode.element,
    ).convert(normalizedRuby);

    return '<ruby>$escapedBase<rt>$escapedRuby</rt></ruby>';
  }
}
