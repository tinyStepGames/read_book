import 'package:flutter_test/flutter_test.dart';
import 'package:read_book/services/background_progress_buffer.dart';

void main() {
  test('バックグラウンド中は作品ごとの最新進捗だけを保持する', () {
    final received = <BackgroundProgressUpdate>[];
    final buffer = BackgroundProgressBuffer((workId, done, total, isRunning) {
      received.add(
        BackgroundProgressUpdate(
          workId: workId,
          done: done,
          total: total,
          isRunning: isRunning,
        ),
      );
    });

    buffer.add(workId: 'work-a', done: 1, total: 10, isRunning: true);
    buffer.add(workId: 'work-a', done: 2, total: 10, isRunning: true);
    buffer.add(workId: 'work-b', done: 3, total: 5, isRunning: true);

    expect(received, isEmpty);

    buffer.flush();

    expect(received, hasLength(2));
    expect(received[0].workId, 'work-a');
    expect(received[0].done, 2);
    expect(received[1].workId, 'work-b');
    expect(received[1].done, 3);
  });

  test('flush後のフォアグラウンド進捗は直ちに通知する', () {
    final received = <BackgroundProgressUpdate>[];
    final buffer = BackgroundProgressBuffer((workId, done, total, isRunning) {
      received.add(
        BackgroundProgressUpdate(
          workId: workId,
          done: done,
          total: total,
          isRunning: isRunning,
        ),
      );
    });

    buffer.flush();
    buffer.add(workId: 'work-a', done: 1, total: 10, isRunning: true);
    buffer.add(workId: 'work-a', done: 2, total: 10, isRunning: true);

    expect(received, hasLength(2));
    expect(received[0].done, 1);
    expect(received[1].done, 2);
  });

  test('再度バックグラウンドへ移動すると通知を再びまとめる', () {
    final received = <BackgroundProgressUpdate>[];
    final buffer = BackgroundProgressBuffer((workId, done, total, isRunning) {
      received.add(
        BackgroundProgressUpdate(
          workId: workId,
          done: done,
          total: total,
          isRunning: isRunning,
        ),
      );
    });

    buffer.flush();
    buffer.beginBatch();

    buffer.add(workId: 'work-a', done: 4, total: 10, isRunning: true);
    buffer.add(workId: 'work-a', done: 5, total: 10, isRunning: true);

    expect(received, isEmpty);

    buffer.flush();

    expect(received, hasLength(1));
    expect(received.single.done, 5);
  });
}
