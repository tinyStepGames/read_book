import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/blocked_author_service.dart';
import '../utils/app_log.dart';
import '../widgets/blocked_authors_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBackupBusy = false;

  Future<void> _openBlockedAuthors() async {
    await showBlockedAuthorsDialog(context);
  }

  Rect _sharePositionOrigin() {
    final renderBox = context.findRenderObject();

    if (renderBox is! RenderBox || !renderBox.hasSize) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    return renderBox.localToGlobal(Offset.zero) & renderBox.size;
  }

  Future<void> _createBackup() async {
    if (_isBackupBusy) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('バックアップを作成'),
          content: const Text(
            'ダウンロードした本文、お気に入り、履歴、'
            '既読情報などをZIPファイルへ保存します。\n\n'
            '表示される共有画面から「ファイルに保存」を選択してください。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('作成'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isBackupBusy = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      messenger.showSnackBar(const SnackBar(content: Text('バックアップを作成しています…')));

      await BackupService().createAndShareBackup(
        sharePositionOrigin: _sharePositionOrigin(),
      );

      if (!mounted) {
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('共有画面から「ファイルに保存」を選択してください。')),
      );
    } catch (error) {
      AppLog.failure('バックアップの作成に失敗しました', error);

      if (!mounted) {
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('バックアップの作成に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          _isBackupBusy = false;
        });
      }
    }
  }

  Future<void> _restoreBackup() async {
    if (_isBackupBusy) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('バックアップから復元'),
          content: const Text(
            'バックアップ作成時点のデータへ戻します。\n\n'
            '現在の作品情報、ダウンロード本文、お気に入り、'
            '履歴、既読情報はバックアップ内のデータに置き換わります。\n\n'
            '復元ファイルを選択しますか？',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('ファイルを選択'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isBackupBusy = true;
    });

    try {
      final staged = await BackupService().selectAndStageRestoreFile();

      if (!mounted || !staged) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('復元の準備ができました'),
            content: const Text(
              'アプリを完全に終了してから、もう一度起動してください。\n\n'
              '次回起動時にバックアップから自動的に復元します。\n\n'
              'iPhoneでは、アプリ切り替え画面でこのアプリを'
              '上へスワイプして終了してください。',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      AppLog.failure('バックアップの読み込みに失敗しました', error);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('バックアップを読み込めませんでした')));
    } finally {
      if (mounted) {
        setState(() {
          _isBackupBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: Column(
        children: [
          if (_isBackupBusy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    '検索',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: BlockedAuthorService.revision,
                  builder: (context, _, _) {
                    final blockedAuthorCount =
                        BlockedAuthorService.entries.length;

                    return ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('ブロック中の作者'),
                      subtitle: Text(
                        blockedAuthorCount == 0
                            ? 'ブロック中の作者はいません'
                            : '$blockedAuthorCount人をブロック中',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openBlockedAuthors,
                    );
                  },
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    'データ',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('バックアップを作成'),
                  subtitle: const Text('本文・お気に入り・履歴などを保存します'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_isBackupBusy,
                  onTap: _isBackupBusy ? null : _createBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('バックアップから復元'),
                  subtitle: const Text('次回起動時に保存済みデータを復元します'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_isBackupBusy,
                  onTap: _isBackupBusy ? null : _restoreBackup,
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '今後、アプリ全体の設定をこの画面へ追加できます。',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
