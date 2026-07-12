import 'package:hive/hive.dart';

import '../models/favorite.dart';
import '../models/work.dart';
import 'narou_api_client.dart';

class UpdateChecker {
  final NarouApiClient _client = NarouApiClient();

  Box<Favorite> get _favoriteBox => Hive.box<Favorite>('favorites');
  Box<Work> get _workBox => Hive.box<Work>('works');

  Future<int> checkAll() async {
    var updatedCount = 0;

    final targets = _favoriteBox.values
        .where((f) => f.targetType == FavoriteTargetType.work && f.autoCheck)
        .toList();

    for (final favorite in targets) {
      final work = _workBox.get(favorite.targetKey);
      if (work == null) continue;

      try {
        final refreshed = await _client.fetchByNcode(work.workId);
        if (refreshed == null) continue;

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
