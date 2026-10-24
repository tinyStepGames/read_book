/// 一括ダウンロードの成功・失敗件数を集計します。
class DownloadBatchTracker {
  DownloadBatchTracker({required this.total}) {
    if (total < 0) {
      throw ArgumentError.value(total, 'total', '0以上である必要があります');
    }
  }

  final int total;

  int succeeded = 0;
  int failed = 0;

  int get processed => succeeded + failed;

  bool get isCompleted => processed == total && failed == 0;

  void recordSuccess() {
    _ensureCanRecord();
    succeeded++;
  }

  void recordFailure() {
    _ensureCanRecord();
    failed++;
  }

  void _ensureCanRecord() {
    if (processed >= total) {
      throw StateError('一括ダウンロードの集計件数が総数を超えています');
    }
  }
}
