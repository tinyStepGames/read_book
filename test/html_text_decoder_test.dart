import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/utils/html_text_decoder.dart';

void main() {
  group('decodeHtmlText', () {
    test('HTML文字参照を復元する', () {
      expect(decodeHtmlText('今日も&quot;超越者&quot;のティータイム'), '今日も"超越者"のティータイム');
    });

    test('二重エンコードされた文字参照を復元する', () {
      expect(decodeHtmlText('&amp;quot;超越者&amp;quot;'), '"超越者"');
    });

    test('通常の日本語は変更しない', () {
      expect(decodeHtmlText('超越者はただ静かに暮らしたい'), '超越者はただ静かに暮らしたい');
    });
  });
}
