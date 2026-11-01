typedef BackgroundDownloadProgressCallback =
    void Function(String workId, int done, int total, bool isRunning);

class BackgroundProgressUpdate {
  const BackgroundProgressUpdate({
    required this.workId,
    required this.done,
    required this.total,
    required this.isRunning,
  });

  final String workId;
  final int done;
  final int total;
  final bool isRunning;
}

/// バックグラウンド中の進捗通知を作品単位でまとめます。
///
/// 本文の保存処理自体は止めず、画面更新通知だけを保留します。
/// アプリ復帰後に[flush]すると、作品ごとの最新状態だけを通知します。
class BackgroundProgressBuffer {
  BackgroundProgressBuffer(this._onProgress);

  final BackgroundDownloadProgressCallback _onProgress;
  final Map<String, BackgroundProgressUpdate> _pending =
      <String, BackgroundProgressUpdate>{};

  bool _isBatching = true;

  bool get isBatching => _isBatching;

  void beginBatch() {
    _isBatching = true;
  }

  void add({
    required String workId,
    required int done,
    required int total,
    required bool isRunning,
  }) {
    final update = BackgroundProgressUpdate(
      workId: workId,
      done: done,
      total: total,
      isRunning: isRunning,
    );

    if (_isBatching) {
      _pending[workId] = update;
      return;
    }

    _emit(update);
  }

  void flush() {
    final updates = _pending.values.toList(growable: false);

    _pending.clear();
    _isBatching = false;

    for (final update in updates) {
      _emit(update);
    }
  }

  void _emit(BackgroundProgressUpdate update) {
    _onProgress(update.workId, update.done, update.total, update.isRunning);
  }
}
