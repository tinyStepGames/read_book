import '../models/download.dart';

/// 保存済み本文と最新目次を照合した結果です。
enum DownloadRefreshDecision {
  refresh,
  unchanged,
  missingIdentity,
  missingEpisode,
  movedEpisode,
  differentIdentity,
}

/// 1話分の判定結果。保存済みDownload自体への参照は保持しません。
class DownloadRefreshItem {
  const DownloadRefreshItem({
    required this.episodeNo,
    required this.decision,
    required this.latestEntry,
  });

  final int episodeNo;
  final DownloadRefreshDecision decision;

  /// 最新目次のコピーです。該当話がない場合は空Mapです。
  final Map<String, String> latestEntry;
}

class DownloadRefreshPlan {
  DownloadRefreshPlan(Iterable<DownloadRefreshItem> items)
    : items = List<DownloadRefreshItem>.unmodifiable(items);

  final List<DownloadRefreshItem> items;

  int get refreshCount => items
      .where((item) => item.decision == DownloadRefreshDecision.refresh)
      .length;

  int get unchangedCount => items
      .where((item) => item.decision == DownloadRefreshDecision.unchanged)
      .length;

  int get skippedCount => items.length - refreshCount - unchangedCount;
}

/// 通信・Hive保存・本文変更を行わない照合処理です。
///
/// 判定後、実際に取得・保存する段階では、URLの安全性、競合、
/// 保存対象の識別情報を改めて確認する必要があります。
abstract final class DownloadRefreshPlanner {
  static DownloadRefreshPlan build({
    required String workId,
    required Iterable<Download> downloads,
    required List<Map<String, String>> episodeList,
    bool forceRefresh = false,
  }) {
    if (workId.trim().isEmpty) {
      throw ArgumentError.value(workId, 'workId', '作品IDが空です');
    }

    final latestByNumber = <int, Map<String, String>>{};
    final latestNumberById = <String, int>{};

    // 最新目次をすべて検証してから、更新対象を判定します。
    // 不正な番号を配列位置などで補完しません。
    for (final entry in episodeList) {
      final number = int.tryParse((entry['episodeNo'] ?? '').trim());

      if (number == null || number <= 0) {
        throw const FormatException('目次の話番号が不正です。');
      }
      if (latestByNumber.containsKey(number)) {
        throw const FormatException('目次の話番号が重複しています。');
      }

      final snapshot = Map<String, String>.unmodifiable(
        Map<String, String>.from(entry),
      );
      latestByNumber[number] = snapshot;

      final id = (entry['sourceId'] ?? '').trim();
      if (id.isNotEmpty) {
        if (latestNumberById.containsKey(id)) {
          throw const FormatException('目次の各話識別子が重複しています。');
        }
        latestNumberById[id] = number;
      }
    }

    final saved = downloads.toList()
      ..sort((left, right) => left.episodeNo.compareTo(right.episodeNo));
    final savedNumbers = <int>{};
    final savedIds = <String>{};

    for (final download in saved) {
      if (download.workId != workId) {
        throw const FormatException('別作品のダウンロードが含まれています。');
      }
      if (download.episodeNo <= 0 || !savedNumbers.add(download.episodeNo)) {
        throw const FormatException('保存済みデータの話番号が不正または重複しています。');
      }

      final id = download.sourceId.trim();
      if (id.isNotEmpty && !savedIds.add(id)) {
        throw const FormatException('保存済みデータの各話識別子が重複しています。');
      }
    }

    final items = <DownloadRefreshItem>[];

    for (final download in saved) {
      final number = download.episodeNo;
      final oldId = download.sourceId.trim();
      final latest = latestByNumber[number];
      final currentNumber = oldId.isEmpty ? null : latestNumberById[oldId];

      DownloadRefreshDecision decision;

      if (oldId.isEmpty) {
        decision = DownloadRefreshDecision.missingIdentity;
      } else if (currentNumber != null && currentNumber != number) {
        // 同じ話が移動していても、既読や読書位置を自動で付け替えません。
        decision = DownloadRefreshDecision.movedEpisode;
      } else if (latest == null) {
        decision = DownloadRefreshDecision.missingEpisode;
      } else {
        final latestId = (latest['sourceId'] ?? '').trim();

        if (latestId.isEmpty) {
          decision = DownloadRefreshDecision.missingIdentity;
        } else if (oldId != latestId) {
          decision = DownloadRefreshDecision.differentIdentity;
        } else {
          final oldStamp = download.sourceUpdatedAt.trim();
          final latestStamp = (latest['sourceUpdatedAt'] ?? '').trim();

          final sameKnownVersion =
              oldStamp.isNotEmpty &&
              latestStamp.isNotEmpty &&
              oldStamp == latestStamp;

          decision = !forceRefresh && sameKnownVersion
              ? DownloadRefreshDecision.unchanged
              : DownloadRefreshDecision.refresh;
        }
      }

      items.add(
        DownloadRefreshItem(
          episodeNo: number,
          decision: decision,
          latestEntry: latest ?? const <String, String>{},
        ),
      );
    }

    return DownloadRefreshPlan(items);
  }
}
