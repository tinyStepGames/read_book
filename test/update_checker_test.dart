import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/models/site.dart';
import 'package:read_book/services/update_checker.dart';

void main() {
  group('UpdateChecker サイト制限', () {
    test('なろう作品を更新確認対象にする', () {
      expect(UpdateChecker.supportsSiteIndex(Site.narou.index), isTrue);
    });

    test('カクヨム作品を更新確認対象にする', () {
      expect(UpdateChecker.supportsSiteIndex(Site.kakuyomu.index), isTrue);
    });

    test('負のサイト番号を拒否する', () {
      expect(UpdateChecker.supportsSiteIndex(-1), isFalse);
    });

    test('範囲外のサイト番号を拒否する', () {
      expect(UpdateChecker.supportsSiteIndex(Site.values.length), isFalse);
    });
  });

  group('UpdateChecker 確認間隔', () {
    final now = DateTime.utc(2026, 1, 2, 12);

    test('未確認なら更新確認する', () {
      expect(UpdateChecker.shouldCheck(lastCheckedAt: null, now: now), isTrue);
    });

    test('6時間以上経過していれば更新確認する', () {
      expect(
        UpdateChecker.shouldCheck(
          lastCheckedAt: now.subtract(const Duration(hours: 6)),
          now: now,
        ),
        isTrue,
      );
    });

    test('6時間未満なら更新確認しない', () {
      expect(
        UpdateChecker.shouldCheck(
          lastCheckedAt: now.subtract(const Duration(hours: 5, minutes: 59)),
          now: now,
        ),
        isFalse,
      );
    });

    test('未来の確認日時は更新確認しない', () {
      expect(
        UpdateChecker.shouldCheck(
          lastCheckedAt: now.add(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('UpdateChecker 話数判定', () {
    test('取得話数が0なら無効', () {
      expect(
        UpdateChecker.decideEpisodeCount(knownCount: 10, fetchedCount: 0),
        UpdateCountDecision.invalid,
      );
    });

    test('基準話数がない場合は通知せず初期化', () {
      expect(
        UpdateChecker.decideEpisodeCount(knownCount: 0, fetchedCount: 10),
        UpdateCountDecision.initialize,
      );
    });

    test('話数増加を更新として判定', () {
      expect(
        UpdateChecker.decideEpisodeCount(knownCount: 10, fetchedCount: 11),
        UpdateCountDecision.increased,
      );
    });

    test('同じ話数なら更新なし', () {
      expect(
        UpdateChecker.decideEpisodeCount(knownCount: 10, fetchedCount: 10),
        UpdateCountDecision.unchanged,
      );
    });

    test('話数減少時は既存値維持', () {
      expect(
        UpdateChecker.decideEpisodeCount(knownCount: 10, fetchedCount: 9),
        UpdateCountDecision.decreased,
      );
    });
  });
}
