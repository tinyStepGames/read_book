import 'package:flutter/material.dart';

import '../services/download_refresh_runner.dart';
import '../utils/app_log.dart';

typedef RunDownloadRefresh =
    Future<DownloadRefreshBatchResult> Function(
      DownloadRefreshCancellation cancellation,
      void Function(int completed, int total) onProgress,
    );

/// 保存済み本文の更新処理を表示します。
///
/// 処理中はダイアログ外タップ・戻る操作では閉じません。
/// 中止は処理中の1話を強制停止せず、後続処理への中止要求です。
/// 全体処理が例外終了した場合、閉じたときの戻り値はnullです。
Future<DownloadRefreshBatchResult?> showDownloadRefreshDialog({
  required BuildContext context,
  required RunDownloadRefresh run,
}) {
  return showDialog<DownloadRefreshBatchResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DownloadRefreshDialog(run: run),
  );
}

class DownloadRefreshDialog extends StatefulWidget {
  const DownloadRefreshDialog({super.key, required this.run});

  final RunDownloadRefresh run;

  @override
  State<DownloadRefreshDialog> createState() => _DownloadRefreshDialogState();
}

class _DownloadRefreshDialogState extends State<DownloadRefreshDialog> {
  final DownloadRefreshCancellation _cancellation =
      DownloadRefreshCancellation();

  DownloadRefreshBatchResult? _result;
  bool _finished = false;
  bool _failed = false;
  bool _started = false;
  int _completed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _start();
      }
    });
  }

  Future<void> _start() async {
    if (_started) {
      return;
    }
    _started = true;

    try {
      final result = await widget.run(_cancellation, (completed, total) {
        if (!mounted ||
            _finished ||
            total < 0 ||
            completed < 0 ||
            completed > total) {
          return;
        }
        setState(() {
          _completed = completed;
          _total = total;
        });
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
        _finished = true;
      });
    } catch (error) {
      AppLog.failure('保存済み本文の更新処理を完了できませんでした', error);
      if (!mounted) {
        return;
      }
      setState(() {
        _failed = true;
        _finished = true;
      });
    }
  }

  void _requestCancellation() {
    if (_finished || _cancellation.isRequested) {
      return;
    }
    setState(() {
      _cancellation.cancel();
    });
  }

  @override
  void dispose() {
    // 親側から強制的に画面を破棄された場合も、後続の開始を止めます。
    if (!_finished) {
      _cancellation.cancel();
    }
    super.dispose();
  }

  Widget _buildProgress() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: _total > 0 ? _completed / _total : null),
        const SizedBox(height: 16),
        Text(_total > 0 ? '確認済み: $_completed/$_total話' : '目次を取得・照合しています…'),
        const SizedBox(height: 12),
        Text(
          _cancellation.isRequested
              ? '中止を要求しました。処理中の取得・保存が終わるまでお待ちください。'
              : '中止しても、処理中の1話は取得・保存が完了するまで続行します。',
        ),
      ],
    );
  }

  Widget _buildResult(DownloadRefreshBatchResult result) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('対象: ${result.totalCount}話'),
        Text('本文更新: ${result.updatedCount}話'),
        Text('タイトルのみ更新: ${result.titleUpdatedCount}話'),
        Text('変更なし: ${result.unchangedCount}話'),
        Text('保留: ${result.skippedCount}話'),
        Text('失敗: ${result.failedCount}話'),
        Text('中止: ${result.canceledCount}話'),
        if (result.skippedCount > 0) ...[
          const SizedBox(height: 12),
          const Text(
            '保留には、識別情報の不足・不一致、話番号の移動、'
            '処理中のローカル変更などが含まれます。',
          ),
        ],
        if (result.failedCount > 0) ...[
          const SizedBox(height: 12),
          const Text('失敗した話があります。すべての話が更新されたわけではありません。'),
        ],
        if (result.totalCount == 0) ...[
          const SizedBox(height: 12),
          const Text('更新対象の保存済み本文はありません。'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return PopScope(
      canPop: _finished,
      child: AlertDialog(
        title: Text(
          !_finished
              ? '保存済み本文を更新中'
              : _failed
              ? '本文更新を完了できませんでした'
              : '本文更新の結果',
        ),
        content: SingleChildScrollView(
          child: !_finished
              ? _buildProgress()
              : _failed
              ? const Text(
                  '目次の取得・照合などでエラーが発生しました。\n'
                  '更新が完了したとは確認できません。'
                  '通信状態などを確認してから、改めて実行してください。',
                )
              : _buildResult(result!),
        ),
        actions: [
          if (!_finished)
            TextButton(
              onPressed: _cancellation.isRequested
                  ? null
                  : _requestCancellation,
              child: Text(_cancellation.isRequested ? '中止要求済み' : '中止'),
            )
          else
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(result);
              },
              child: const Text('閉じる'),
            ),
        ],
      ),
    );
  }
}
