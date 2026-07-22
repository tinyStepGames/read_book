import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../utils/novel_body_codec.dart';

/// ルビ・傍点などの装飾に対応した小説本文表示です。
class DecoratedNovelText extends StatelessWidget {
  final String body;
  final double fontSize;

  const DecoratedNovelText({
    super.key,
    required this.body,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;

    final bodyStyle = defaultStyle.copyWith(fontSize: fontSize, height: 1.65);

    // 過去に保存した本文は、従来どおり通常のTextで表示します。
    if (!NovelBodyCodec.isRichBody(body)) {
      return Text(body, style: bodyStyle);
    }

    final payload = NovelBodyCodec.payloadOf(
      body,
    ).replaceAll(RegExp(r'\n[ \t]*\n(?:[ \t]*\n)+'), '\n\n');

    final fragment = html_parser.parseFragment(payload);

    final spans = _buildNodes(fragment.nodes, bodyStyle);

    return SelectionArea(
      child: RichText(
        text: TextSpan(style: bodyStyle, children: spans),
      ),
    );
  }

  List<InlineSpan> _buildNodes(List<dom.Node> nodes, TextStyle currentStyle) {
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      spans.addAll(_buildNode(node, currentStyle));
    }

    return spans;
  }

  List<InlineSpan> _buildNode(dom.Node node, TextStyle currentStyle) {
    if (node is dom.Text) {
      return <InlineSpan>[TextSpan(text: node.data, style: currentStyle)];
    }

    if (node is! dom.Element) {
      return const <InlineSpan>[];
    }

    final tag = (node.localName ?? '').toLowerCase();

    switch (tag) {
      case 'ruby':
        return <InlineSpan>[_buildRubySpan(node, currentStyle)];

      case 'em':
        if (node.attributes['data-novel-emphasis'] == 'dot' ||
            node.classes.contains('emphasisDots')) {
          return <InlineSpan>[_buildEmphasisSpan(node.text, currentStyle)];
        }

        return <InlineSpan>[
          TextSpan(
            style: currentStyle.copyWith(fontStyle: FontStyle.italic),
            children: _buildNodes(
              node.nodes,
              currentStyle.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ];

      case 'strong':
      case 'b':
        final style = currentStyle.copyWith(fontWeight: FontWeight.bold);

        return <InlineSpan>[
          TextSpan(style: style, children: _buildNodes(node.nodes, style)),
        ];

      case 'i':
        final style = currentStyle.copyWith(fontStyle: FontStyle.italic);

        return <InlineSpan>[
          TextSpan(style: style, children: _buildNodes(node.nodes, style)),
        ];

      case 'u':
        final style = currentStyle.copyWith(
          decoration: TextDecoration.underline,
        );

        return <InlineSpan>[
          TextSpan(style: style, children: _buildNodes(node.nodes, style)),
        ];

      case 's':
      case 'strike':
      case 'del':
        final style = currentStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        );

        return <InlineSpan>[
          TextSpan(style: style, children: _buildNodes(node.nodes, style)),
        ];

      case 'br':
        return const <InlineSpan>[TextSpan(text: '\n')];

      case 'hr':
        return <InlineSpan>[
          TextSpan(
            text: '\n────────────\n',
            style: currentStyle.copyWith(
              color: currentStyle.color?.withValues(alpha: 0.45),
            ),
          ),
        ];

      default:
        // 未知のタグは、装飾を外して中の文章だけを表示します。
        return _buildNodes(node.nodes, currentStyle);
    }
  }

  InlineSpan _buildRubySpan(dom.Element rubyElement, TextStyle bodyStyle) {
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

    if (normalizedRuby.isEmpty) {
      return TextSpan(text: baseText, style: bodyStyle);
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: _AnnotationText(
        baseText: baseText,
        annotationText: normalizedRuby,
        bodyStyle: bodyStyle,
        annotationScale: 0.5,
      ),
    );
  }

  InlineSpan _buildEmphasisSpan(String text, TextStyle bodyStyle) {
    if (text.isEmpty) {
      return const TextSpan(text: '');
    }

    return TextSpan(
      children: [
        for (final rune in text.runes)
          WidgetSpan(
            alignment: PlaceholderAlignment.bottom,
            child: _AnnotationText(
              baseText: String.fromCharCode(rune),
              annotationText: '・',
              bodyStyle: bodyStyle,
              annotationScale: 0.55,
            ),
          ),
      ],
    );
  }
}

/// 親文字の上にルビまたは傍点を表示します。
class _AnnotationText extends StatelessWidget {
  final String baseText;
  final String annotationText;
  final TextStyle bodyStyle;
  final double annotationScale;

  const _AnnotationText({
    required this.baseText,
    required this.annotationText,
    required this.bodyStyle,
    required this.annotationScale,
  });

  @override
  Widget build(BuildContext context) {
    final baseFontSize = bodyStyle.fontSize ?? 16;
    final annotationFontSize = baseFontSize * annotationScale;

    final textColor =
        bodyStyle.color ?? DefaultTextStyle.of(context).style.color;

    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            annotationText,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: bodyStyle.copyWith(
              fontSize: annotationFontSize,
              height: 1,
              color: textColor,
              fontWeight: FontWeight.normal,
              fontStyle: FontStyle.normal,
              decoration: TextDecoration.none,
            ),
          ),
          Text(
            baseText,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: bodyStyle.copyWith(height: 1),
          ),
        ],
      ),
    );
  }
}
