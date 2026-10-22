import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/services/update_checker.dart';

void main() {
  group('UpdateChecker サイト制限', () {
    test('なろう作品を更新確認対象にする', () {
      expect(UpdateChecker.supportsSiteIndex(Site.narou.index), isTrue);
    });

    test('カクヨム作品をなろうAPIの対象にしない', () {
      expect(UpdateChecker.supportsSiteIndex(Site.kakuyomu.index), isFalse);
    });

    test('負のサイト番号を拒否する', () {
      expect(UpdateChecker.supportsSiteIndex(-1), isFalse);
    });

    test('範囲外のサイト番号を拒否する', () {
      expect(UpdateChecker.supportsSiteIndex(Site.values.length), isFalse);
    });
  });
}
