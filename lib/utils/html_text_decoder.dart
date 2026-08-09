import 'package:html/parser.dart' as html_parser;

/// APIなどから取得した文字列に含まれるHTML文字参照を復元します。
///
/// 二重にエンコードされた `&amp;quot;` などにも対応するため、
/// 最大3回までデコードします。
String decodeHtmlText(String value) {
  var decoded = value;

  for (var index = 0; index < 3; index++) {
    final next = html_parser.parseFragment(decoded).text ?? '';

    if (next == decoded) {
      break;
    }

    decoded = next;
  }

  return decoded;
}
