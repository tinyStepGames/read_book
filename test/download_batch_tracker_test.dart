import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/download_batch_tracker.dart';

void main() {
  group('DownloadBatchTracker', () {
    test('すべて成功した場合だけ完了になる', () {
      final tracker = DownloadBatchTracker(total: 2);

      tracker.recordSuccess();
      expect(tracker.isCompleted, isFalse);

      tracker.recordSuccess();

      expect(tracker.succeeded, 2);
      expect(tracker.failed, 0);
      expect(tracker.processed, 2);
      expect(tracker.isCompleted, isTrue);
    });

    test('失敗がある場合は全件処理後も未完了になる', () {
      final tracker = DownloadBatchTracker(total: 3);

      tracker.recordSuccess();
      tracker.recordFailure();
      tracker.recordSuccess();

      expect(tracker.succeeded, 2);
      expect(tracker.failed, 1);
      expect(tracker.processed, 3);
      expect(tracker.isCompleted, isFalse);
    });

    test('失敗した話を成功件数へ含めない', () {
      final tracker = DownloadBatchTracker(total: 2);

      tracker.recordFailure();
      tracker.recordSuccess();

      expect(tracker.succeeded, 1);
      expect(tracker.failed, 1);
    });

    test('総数を超える記録を拒否する', () {
      final tracker = DownloadBatchTracker(total: 1);

      tracker.recordSuccess();

      expect(tracker.recordFailure, throwsStateError);
    });

    test('負の総数を拒否する', () {
      expect(() => DownloadBatchTracker(total: -1), throwsArgumentError);
    });
  });
}
