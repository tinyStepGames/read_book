import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/favorite_color.dart';
import '../models/site.dart';
import '../services/narou_api_client.dart';
import '../widgets/favorite_star_button.dart';



class ExpandableWorkCard extends StatefulWidget {
  final NarouSearchResult work;
  final FavoriteColor? favoriteColor;
  final ValueChanged<FavoriteColor?> onFavoriteChanged;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onDownload;
  final ValueChanged<String>? onSearchAuthor;
  final ValueChanged<String>? onSearchTag;
  final bool hasAnyRead;
  final bool hasAnyDownload;
  final VoidCallback? onDeleteDownload;
  final VoidCallback? onDeleteRead;

  const ExpandableWorkCard({
    super.key,
    required this.work,
    required this.favoriteColor,
    required this.onFavoriteChanged,
    this.onOpenDetail,
    this.onDownload,
    this.onSearchAuthor,
    this.onSearchTag,
    this.hasAnyRead = false,
    this.hasAnyDownload = false,
    this.onDeleteDownload,
    this.onDeleteRead,
  });

  @override
  State<ExpandableWorkCard> createState() => _ExpandableWorkCardState();
}

class _ExpandableWorkCardState extends State<ExpandableWorkCard> {
  bool _expanded = false;

  List<String> get _tags => widget.work.keyword
      .split(' ')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _showMoreMenu(BuildContext context) async {
    final result = widget.work;
    final tags = _tags;

    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'favorite'),
            child: const Text('お気に入り登録'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'download'),
            child: const Text('ダウンロード'),
          ),
          if (widget.hasAnyDownload)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(sheetContext, 'delete_download'),
              child: const Text('ダウンロードファイルの削除'),
            ),
          if (widget.hasAnyRead)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(sheetContext, 'delete_read'),
              child: const Text('既読の削除(キャッシュも消す)'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'author'),
            child: Text('作者:${result.author}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'tag'),
            child: Text('タグ (${tags.length})'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('キャンセル'),
        ),
      ),
    );

    if (!mounted) return;

    if (selected == 'favorite') {
      if (widget.favoriteColor == null) {
        widget.onFavoriteChanged(FavoriteColor.blue);
      } else {
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('すでにお気に入りに登録されています')),
        );
      }
    } else if (selected == 'download') {
      widget.onDownload?.call();
    } else if (selected == 'delete_download') {
      widget.onDeleteDownload?.call();
    } else if (selected == 'delete_read') {
      widget.onDeleteRead?.call();
    } else if (selected == 'author') {
      widget.onSearchAuthor?.call(result.author);
    } else if (selected == 'tag') {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      await _showTagMenu(context, tags);
    }
  }

  Future<void> _showTagMenu(BuildContext context, List<String> tags) async {
    if (tags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タグが登録されていません')),
      );
      return;
    }

    final selectedTag = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          for (final tag in tags)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, tag),
              child: Text(tag),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('キャンセル'),
        ),
      ),
    );

    if (!mounted) return;
    if (selectedTag != null) {
      widget.onSearchTag?.call(selectedTag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.work;
    final theme = Theme.of(context);
    final isRead = widget.hasAnyRead;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: FavoriteStarButton(
                    currentColor: widget.favoriteColor,
                    onColorSelected: widget.onFavoriteChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${result.statusLabel}] ${result.title}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isRead ? Colors.grey[500] : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
  '作:${result.author}　サイト:${result.site.displayName}',
  style: theme.textTheme.bodySmall?.copyWith(
    fontSize: 12,
    color: isRead ? Colors.grey[600] : Colors.grey[400],
  ),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
),

                      const SizedBox(height: 1),
                      Text(
                        '更新日:${result.generalLastup}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: isRead ? Colors.grey[600] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showMoreMenu(context),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                    if (widget.hasAnyDownload)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Icon(
                          Icons.download_done,
                          size: 14,
                          color: Colors.teal[300],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              Text(
                result.summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: isRead ? Colors.grey[600] : null,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '文字数:${result.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'お気に入り人数:${result.favNovelCnt}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tags
                      .map(
                        (k) => Text(
                          k,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.onOpenDetail,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('詳細・目次を見る', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
            const SizedBox(height: 6),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}
