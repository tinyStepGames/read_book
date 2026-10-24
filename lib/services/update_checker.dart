import 'package:hive/hive.dart';

import '../models/favorite.dart';
import '../models/site.dart';
import '../models/work.dart';
import 'kakuyomu_scraper.dart';
import 'narou_api_client.dart';

/// 取得した作品の更新情報です。
class UpdateCheckSnapshot {
  const UpdateCheckSnapshot({required this.episodeCount, this.isCompleted});

  final int episodeCount;

  /// 完結状態を安全に取得できないサイトではnullです。
  final bool? isCompleted;
}

/// 保存済み話数と取得話数の比較結果です。
enum UpdateCountDecision {
  /// 取得結果が0以下であり、更新判定に使用できません。
  invalid,

  /// 保存済み基準値がないため、通知せず現在値を基準にします。
  initialize,

  /// 保存済み話数と同じです。
  unchanged,

  /// 話数が増加しています。
  increased,

  /// 取得話数が保存済み話数より少ないため、既存値を維持します。
  decreased,
}

class UpdateChecker {
  UpdateChecker({
    NarouApiClient? client,
    KakuyomuScraper? kakuyomuScraper,
    DateTime Function()? now,
  }) : _client = client ?? NarouApiClient(),
       _kakuyomuScraper = kakuyomuScraper ?? KakuyomuScraper(),
       _now = now ?? DateTime.now;

  static const Duration minimumCheckInterval = Duration(hours: 6);

  final NarouApiClient _client;
  final KakuyomuScraper _kakuyomuScraper;
  final DateTime Function() _now;

  Box<Favorite> get _favoriteBox => Hive.box<Favorite>('favorites');
  Box<Work> get _workBox => Hive.box<Work>('works');

  /// 自動更新確認に対応しているサイトか判定します。
  static bool supportsSiteIndex(int siteIndex) {
    if (siteIndex < 0 || siteIndex >= Site.values.length) {
      return false;
    }

    final site = Site.values[siteIndex];

    return site == Site.narou || site == Site.kakuyomu;
  }

  /// 前回確認から十分な時間が経過しているか判定します。
  static bool shouldCheck({
    required DateTime? lastCheckedAt,
    required DateTime now,
    Duration minimumInterval = minimumCheckInterval,
  }) {
    if (lastCheckedAt == null) {
      return true;
    }

    final elapsed = now.difference(lastCheckedAt);

    return !elapsed.isNegative && elapsed >= minimumInterval;
  }

  /// 取得話数を既存の基準値へ適用できるか判定します。
  static UpdateCountDecision decideEpisodeCount({
    required int knownCount,
    required int fetchedCount,
  }) {
    if (fetchedCount <= 0) {
      return UpdateCountDecision.invalid;
    }

    if (knownCount <= 0) {
      return UpdateCountDecision.initialize;
    }

    if (fetchedCount > knownCount) {
      return UpdateCountDecision.increased;
    }

    if (fetchedCount < knownCount) {
      return UpdateCountDecision.decreased;
    }

    return UpdateCountDecision.unchanged;
  }

  Future<UpdateCheckSnapshot?> _fetchSnapshot(Work work) async {
    final site = Site.values[work.siteIndex];

    switch (site) {
      case Site.narou:
        final refreshed = await _client.fetchByNcode(work.workId);

        if (refreshed == null || refreshed.generalAllNo <= 0) {
          return null;
        }

        return UpdateCheckSnapshot(
          episodeCount: refreshed.generalAllNo,
          isCompleted: refreshed.isCompleted,
        );

      case Site.kakuyomu:
        final episodes = await _kakuyomuScraper.fetchEpisodeList(work.workId);

        if (episodes.isEmpty) {
          return null;
        }

        return UpdateCheckSnapshot(episodeCount: episodes.length);
    }
  }

  Future<int> checkAll() async {
    var updatedCount = 0;

    final targets = _favoriteBox.values
        .where(
          (favorite) =>
              favorite.targetType == FavoriteTargetType.work &&
              favorite.autoCheck,
        )
        .toList();

    for (final favorite in targets) {
      final work = _workBox.get(favorite.targetKey);

      if (work == null || !supportsSiteIndex(work.siteIndex)) {
        continue;
      }

      final now = _now();

      if (!shouldCheck(lastCheckedAt: favorite.lastCheckedAt, now: now)) {
        continue;
      }

      try {
        final snapshot = await _fetchSnapshot(work);

        if (snapshot == null) {
          continue;
        }

        final decision = decideEpisodeCount(
          knownCount: favorite.lastKnownEpisodeCount,
          fetchedCount: snapshot.episodeCount,
        );

        if (decision == UpdateCountDecision.invalid) {
          continue;
        }

        favorite.lastCheckedAt = now;

        switch (decision) {
          case UpdateCountDecision.invalid:
            break;

          case UpdateCountDecision.initialize:
            // 過去データなど基準値がない場合は、現在話数を基準にします。
            // 既存の全話を新着として通知しないためです。
            favorite.lastKnownEpisodeCount = snapshot.episodeCount;
            break;

          case UpdateCountDecision.increased:
            favorite.hasUnseenUpdate = true;
            favorite.lastKnownEpisodeCount = snapshot.episodeCount;
            updatedCount++;

          case UpdateCountDecision.unchanged:
          case UpdateCountDecision.decreased:
            // サイト側の一時的な欠落や非公開化で保存値を減らしません。
            break;
        }

        var workChanged = false;

        if (snapshot.episodeCount > work.totalEpisodeCount) {
          work.totalEpisodeCount = snapshot.episodeCount;
          work.lastUpdatedAt = now;
          workChanged = true;
        }

        final completed = snapshot.isCompleted;

        if (completed != null && completed != work.isCompleted) {
          work.isCompleted = completed;
          workChanged = true;
        }

        if (workChanged) {
          await work.save();
        }

        await favorite.save();
      } catch (_) {
        // 通信失敗やサイト構造変更時は既存値を変更しません。
        continue;
      }
    }

    return updatedCount;
  }
}
