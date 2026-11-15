import 'package:flutter/material.dart';

import '../services/download_refresh_runner.dart';
import '../services/download_refresh_planner.dart';
import '../utils/app_log.dart';

/// 本文再取得がある場合に、通信開始前の予定を確認します。
/// 予定件数は結果の保証ではなく、実行時の競合などで保留になり得ます。
Future<bool> confirmDownloadRefreshPlan({
  required BuildContext context,
  required DownloadRefreshPlan plan,
}) async {
  if (plan.refreshCount == 0) {
    return true;
  }

  final unknownCount = plan.items
      .where((item) => item.decision == DownloadRefreshDecision.missingRevision)
      .length;
  final otherSkipped = plan.skippedCount - unknownCount;

  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('本文再取得の予定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('保存済みの照合対象: ${plan.items.length}話'),
            Text('本文の再取得予定: ${plan.refreshCount}話'),
            Text('既知の同じ版・本文取得なし: ${plan.unchangedCount}話'),
            Text('更新日時不明・本文未確認で保留: $unknownCount話'),
            Text('その他の保留予定: $otherSkipped話'),
            const SizedBox(height: 12),
            const Text(
              '通信・挿絵の取得時間と、取得間隔の待機が必要です。'
              '再取得予定が多い場合は時間がかかります。',
            ),
            const SizedBox(height: 8),
            const Text(
              '実行時に削除・変更された話などは保留になります。'
              '新着話の追加ダウンロードは行いません。',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('decline-download-refresh-plan'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('実行しない'),
        ),
        FilledButton(
          key: const ValueKey('accept-download-refresh-plan'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('この内容で実行'),
        ),
      ],
    ),
  );
  return accepted == true;
}

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
        if (result.unknownRevisionCount > 0)
          Text('うち更新日時不明: ${result.unknownRevisionCount}話（本文未確認）'),
        Text('失敗: ${result.failedCount}話'),
        Text('中止: ${result.canceledCount}話'),
        if (result.skippedCount > 0) ...[
          const SizedBox(height: 12),
          const Text(
            '保留には、識別情報の不足・不一致、話番号の移動、'
            '処理中のローカル変更などが含まれます。',
          ),
        ],
        if (result.unknownRevisionCount > 0) ...[
          const SizedBox(height: 12),
          const Text(
            '更新日時不明の話は「変更なし」と確認できたわけではありません。'
            '本文を確認する場合は、再取得オプションをオンにして実行してください。',
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
