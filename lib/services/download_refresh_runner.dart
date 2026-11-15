import '../utils/app_log.dart';
import 'download_refresh_planner.dart';

typedef RefreshDownloadedItem = Future<bool> Function(DownloadRefreshItem item);

enum DownloadRefreshOutcome {
  updated,
  titleUpdated,
  failed,
  skipped,
  unchanged,
  canceled,
}

class DownloadRefreshItemResult {
  const DownloadRefreshItemResult({required this.item, required this.outcome});

  final DownloadRefreshItem item;
  final DownloadRefreshOutcome outcome;
}

class DownloadRefreshBatchResult {
  DownloadRefreshBatchResult(Iterable<DownloadRefreshItemResult> items)
    : items = List<DownloadRefreshItemResult>.unmodifiable(items);

  final List<DownloadRefreshItemResult> items;

  int _count(DownloadRefreshOutcome outcome) =>
      items.where((item) => item.outcome == outcome).length;

  int get updatedCount => _count(DownloadRefreshOutcome.updated);
  int get titleUpdatedCount => _count(DownloadRefreshOutcome.titleUpdated);
  int get failedCount => _count(DownloadRefreshOutcome.failed);
  int get skippedCount => _count(DownloadRefreshOutcome.skipped);
  int get unchangedCount => _count(DownloadRefreshOutcome.unchanged);
  int get canceledCount => _count(DownloadRefreshOutcome.canceled);

  /// 保留のうち、更新日時が不明で本文を再確認しなかった件数です。
  /// skippedCountの内数であり、別途加算しません。
  int get unknownRevisionCount => items
      .where(
        (item) =>
            item.outcome == DownloadRefreshOutcome.skipped &&
            item.item.decision == DownloadRefreshDecision.missingRevision,
      )
      .length;

  int get totalCount => items.length;
}

/// キャンセルは処理中の1話を中断せず、次の処理開始前に確認します。
class DownloadRefreshCancellation {
  bool _requested = false;

  bool get isRequested => _requested;

  void cancel() {
    _requested = true;
  }
}

/// 更新計画を直列実行します。通信やHiveの具体的な処理は注入します。
///
/// 重複防止はこのインスタンス内で有効です。
/// 接続時は作品更新を同じインスタンスへ集約する必要があります。
class DownloadRefreshRunner {
  DownloadRefreshRunner({
    this.interval = const Duration(seconds: 1),
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? ((duration) => Future<void>.delayed(duration)) {
    if (interval.isNegative) {
      throw ArgumentError.value(interval, 'interval', '待機時間が負です');
    }
  }

  final Duration interval;
  final Future<void> Function(Duration) _delay;
  final Set<String> _activeWorks = <String>{};

  Future<DownloadRefreshBatchResult> run({
    required String workId,
    required DownloadRefreshPlan plan,
    required RefreshDownloadedItem refreshItem,
    Future<DownloadRefreshOutcome> Function(DownloadRefreshItem item)?
    refreshUnchangedItem,
    DownloadRefreshCancellation? cancellation,
    void Function(int completed, int total)? onProgress,
  }) async {
    final normalizedWorkId = workId.trim();
    if (normalizedWorkId.isEmpty) {
      throw ArgumentError.value(workId, 'workId', '作品IDが空です');
    }

    final numbers = <int>{};
    for (final item in plan.items) {
      if (item.episodeNo <= 0 || !numbers.add(item.episodeNo)) {
        throw const FormatException('更新計画の話番号が不正または重複しています。');
      }
    }

    if (!_activeWorks.add(normalizedWorkId)) {
      throw StateError('この作品の更新処理はすでに実行中です。');
    }

    final results = <DownloadRefreshItemResult>[];
    var hasAttemptedRefresh = false;

    void notifyProgress() {
      try {
        onProgress?.call(results.length, plan.items.length);
      } catch (error) {
        // 表示側の例外を、成功済み本文の更新失敗として扱いません。
        AppLog.failure('本文更新の進捗通知に失敗しました', error);
      }
    }

    void cancelRemaining(int start) {
      for (var index = start; index < plan.items.length; index++) {
        results.add(
          DownloadRefreshItemResult(
            item: plan.items[index],
            outcome: DownloadRefreshOutcome.canceled,
          ),
        );
      }
      notifyProgress();
    }

    try {
      for (var index = 0; index < plan.items.length; index++) {
        if (cancellation?.isRequested ?? false) {
          cancelRemaining(index);
          break;
        }

        final item = plan.items[index];
        DownloadRefreshOutcome outcome;

        if (item.decision == DownloadRefreshDecision.unchanged) {
          if (refreshUnchangedItem == null) {
            outcome = DownloadRefreshOutcome.unchanged;
          } else {
            try {
              outcome = await refreshUnchangedItem(item);
              if (outcome != DownloadRefreshOutcome.titleUpdated &&
                  outcome != DownloadRefreshOutcome.unchanged &&
                  outcome != DownloadRefreshOutcome.skipped) {
                throw StateError('タイトル更新の処理結果が不正です。');
              }
            } catch (error) {
              AppLog.failure('保存済み各話タイトルの更新に失敗しました', error);
              outcome = DownloadRefreshOutcome.failed;
            }
          }
        } else if (item.decision != DownloadRefreshDecision.refresh) {
          outcome = DownloadRefreshOutcome.skipped;
        } else {
          if (hasAttemptedRefresh && interval > Duration.zero) {
            await _delay(interval);
          }

          // 待機中にキャンセルされた場合も、次の取得は開始しません。
          if (cancellation?.isRequested ?? false) {
            cancelRemaining(index);
            break;
          }

          hasAttemptedRefresh = true;

          try {
            final updated = await refreshItem(item);
            outcome = updated
                ? DownloadRefreshOutcome.updated
                : DownloadRefreshOutcome.skipped;
          } catch (error) {
            AppLog.failure('保存済み本文の更新に失敗しました', error);
            outcome = DownloadRefreshOutcome.failed;
          }
        }

        results.add(DownloadRefreshItemResult(item: item, outcome: outcome));
        notifyProgress();
      }

      return DownloadRefreshBatchResult(results);
    } finally {
      _activeWorks.remove(normalizedWorkId);
    }
  }
}
