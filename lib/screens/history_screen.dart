import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';

import '../models/history_entry.dart';
import '../models/work.dart';
import '../services/download_manager.dart';
import '../services/novel_repository.dart';
import '../services/search_request_controller.dart';
import '../utils/no_animation_route.dart';
import 'reader_screen.dart';

enum _HistoryMenuAction { download, searchTitle, searchAuthor, deleteHistory }

class HistoryScreen extends StatefulWidget {
  final NovelRepository repository;
  final SearchRequestController searchRequestController;
  final VoidCallback onNavigateToSearch;

  const HistoryScreen({
    super.key,
    required this.repository,
    required this.searchRequestController,
    required this.onNavigateToSearch,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  Future<void> _downloadEpisode(Work work, HistoryEntry entry) async {
    if (widget.repository.isDownloaded(work, entry.episodeNo)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('この話はダウンロード済みです')));
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('第${entry.episodeNo}話のダウンロードを開始します')),
      );

      await DownloadManager.instance.downloadSingle(
        work: work,
        episodeNo: entry.episodeNo,
        episodeTitle: entry.episodeTitle ?? '',
      );

      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('第${entry.episodeNo}話をダウンロードしました')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ダウンロードに失敗しました: $e')));
    }
  }

  void _searchByTitle(Work work) {
    widget.searchRequestController.request(
      SearchRequest(
        keyword: work.title,
        order: 'new',
        authorNameOnly: false,
        keywordOnly: false,
        siteIndex: work.siteIndex,
      ),
    );

    widget.onNavigateToSearch();
  }

  void _searchByAuthor(Work work) {
    if (work.author.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('作者名が登録されていません')));
      return;
    }

    widget.searchRequestController.request(
      SearchRequest(
        keyword: work.author,
        order: 'new',
        authorNameOnly: true,
        keywordOnly: false,
        siteIndex: work.siteIndex,
      ),
    );

    widget.onNavigateToSearch();
  }

  Future<void> _deleteHistory(HistoryEntry entry, Work work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('履歴を削除'),
          content: Text(
            '「${work.title}」の第${entry.episodeNo}話を'
            '履歴から削除しますか？\n\n'
            '既読情報、キャッシュ、ダウンロードファイルは削除されません。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('削除'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    await entry.delete();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('履歴を削除しました')));
  }

  Future<void> _handleMenuAction(
    _HistoryMenuAction action,
    HistoryEntry entry,
    Work work,
  ) async {
    switch (action) {
      case _HistoryMenuAction.download:
        await _downloadEpisode(work, entry);
        break;

      case _HistoryMenuAction.searchTitle:
        _searchByTitle(work);
        break;

      case _HistoryMenuAction.searchAuthor:
        _searchByAuthor(work);
        break;

      case _HistoryMenuAction.deleteHistory:
        await _deleteHistory(entry, work);
        break;
    }
  }

  Future<void> _openReader(Work work, HistoryEntry entry) async {
    await Navigator.of(context).push<void>(
      noAnimationRoute<void>(
        ReaderScreen(
          repository: widget.repository,
          work: work,
          episodeNo: entry.episodeNo,
          episodeTitle: entry.episodeTitle ?? '',
        ),
      ),
    );

    if (!mounted) return;

    // 本文から戻った後、ダウンロード表示などを更新する
    setState(() {});
  }

  Widget _buildActionLabel(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool destructive = false,
    bool disabled = false,
  }) {
    Color color;

    if (disabled) {
      color = CupertinoColors.inactiveGray.resolveFrom(context);
    } else if (destructive) {
      color = CupertinoColors.systemRed.resolveFrom(context);
    } else {
      color = CupertinoColors.activeBlue.resolveFrom(context);
    }

    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          SizedBox(width: 28, child: Icon(icon, size: 21, color: color)),
          Expanded(
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, color: color),
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Future<void> _showHistoryMenu(HistoryEntry entry, Work work) async {
    final downloaded = widget.repository.isDownloaded(work, entry.episodeNo);

    final selected = await showCupertinoModalPopup<_HistoryMenuAction>(
      context: context,
      barrierDismissible: true,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          title: Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          message: Text(
            '第${entry.episodeNo}話'
            '${entry.episodeTitle?.isNotEmpty ?? false ? '　${entry.episodeTitle}' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (downloaded)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                },
                child: _buildActionLabel(
                  sheetContext,
                  icon: CupertinoIcons.check_mark_circled,
                  label: 'ダウンロード済み',
                  disabled: true,
                ),
              )
            else
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext, _HistoryMenuAction.download);
                },
                child: _buildActionLabel(
                  sheetContext,
                  icon: CupertinoIcons.cloud_download,
                  label: 'ダウンロード',
                ),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, _HistoryMenuAction.searchTitle);
              },
              child: _buildActionLabel(
                sheetContext,
                icon: CupertinoIcons.search,
                label: '本の名前で検索',
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, _HistoryMenuAction.searchAuthor);
              },
              child: _buildActionLabel(
                sheetContext,
                icon: CupertinoIcons.person_crop_circle,
                label: '作者：${work.author}',
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext, _HistoryMenuAction.deleteHistory);
              },
              child: _buildActionLabel(
                sheetContext,
                icon: CupertinoIcons.delete,
                label: '履歴削除',
                destructive: true,
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
            },
            child: const Text(
              'キャンセル',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    await _handleMenuAction(selected, entry, work);
  }

  Widget _buildTrailing(Work work, HistoryEntry entry) {
    final downloaded = widget.repository.isDownloaded(work, entry.episodeNo);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 既読マーク
        const Icon(Icons.check, color: Colors.grey, size: 20),

        const SizedBox(width: 4),

        // ダウンロード済みマーク
        if (downloaded) ...[
          const Icon(Icons.download_done, color: Colors.teal, size: 17),
          const SizedBox(width: 4),
        ],

        // 三点リーダー。GestureDetectorなので波紋は出ない
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _showHistoryMenu(entry, work);
          },
          child: const SizedBox(
            width: 36,
            height: 44,
            child: Center(
              child: Icon(Icons.more_vert, color: Colors.grey, size: 21),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('履歴')),
      body: ValueListenableBuilder<Box<HistoryEntry>>(
        valueListenable: Hive.box<HistoryEntry>('history').listenable(),
        builder: (context, box, _) {
          final entries = box.values.toList()
            ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));

          if (entries.isEmpty) {
            return const Center(child: Text('読書履歴はまだありません'));
          }

          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) {
              return const Divider(height: 1);
            },
            itemBuilder: (context, index) {
              final entry = entries[index];
              final work = widget.repository.getWork(entry.workId);

              if (work == null) {
                return const SizedBox.shrink();
              }

              final hasEpisodeTitle =
                  entry.episodeTitle?.trim().isNotEmpty ?? false;

              final episodeTitlePart = hasEpisodeTitle
                  ? '　${entry.episodeTitle}'
                  : '';

              final headline =
                  '${work.title} '
                  '第${entry.episodeNo}話'
                  '$episodeTitlePart';

              return ListTile(
                title: Text(
                  headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  '作:${work.author}　サイト:なろう\n'
                  'アクセス日: '
                  '${_dateFormat.format(entry.lastReadAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                isThreeLine: true,
                trailing: _buildTrailing(work, entry),
                onTap: () {
                  _openReader(work, entry);
                },
              );
            },
          );
        },
      ),
    );
  }
}
