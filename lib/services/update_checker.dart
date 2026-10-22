import 'package:hive/hive.dart';

import '../models/favorite.dart';
import '../models/site.dart';
import '../models/work.dart';
import 'narou_api_client.dart';

class UpdateChecker {
  UpdateChecker({NarouApiClient? client})
    : _client = client ?? NarouApiClient();

  final NarouApiClient _client;

  Box<Favorite> get _favoriteBox => Hive.box<Favorite>('favorites');
  Box<Work> get _workBox => Hive.box<Work>('works');

  /// 現在、自動更新確認に対応しているサイトか判定します。
  ///
  /// カクヨム作品をなろうAPIへ送信しないため、
  /// なろう以外は更新確認対象から除外します。
  static bool supportsSiteIndex(int siteIndex) {
    if (siteIndex < 0 || siteIndex >= Site.values.length) {
      return false;
    }

    return Site.values[siteIndex] == Site.narou;
  }

  Future<int> checkAll() async {
    var updatedCount = 0;

    final targets = _favoriteBox.values
        .where((f) => f.targetType == FavoriteTargetType.work && f.autoCheck)
        .toList();

    for (final favorite in targets) {
      final work = _workBox.get(favorite.targetKey);

      if (work == null || !supportsSiteIndex(work.siteIndex)) {
        continue;
      }

      try {
        final refreshed = await _client.fetchByNcode(work.workId);

        if (refreshed == null) {
          continue;
        }

        favorite.lastCheckedAt = DateTime.now();

        if (refreshed.generalAllNo > favorite.lastKnownEpisodeCount) {
          favorite.hasUnseenUpdate = true;
          favorite.lastKnownEpisodeCount = refreshed.generalAllNo;
          updatedCount++;

          work.totalEpisodeCount = refreshed.generalAllNo;
          work.lastUpdatedAt = DateTime.now();
          work.isCompleted = refreshed.isCompleted;
          await work.save();
        }

        await favorite.save();
      } catch (_) {
        continue;
      }
    }

    return updatedCount;
  }
}
