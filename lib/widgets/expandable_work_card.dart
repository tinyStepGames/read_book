import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/favorite_color.dart';
import '../models/site.dart';
import '../services/narou_api_client.dart';
import '../widgets/favorite_star_button.dart';

typedef SearchAuthorCallback = void Function(String author, String authorId);
typedef LoadWorkSummaryCallback = Future<String> Function();

class ExpandableWorkCard extends StatefulWidget {
  final NarouSearchResult work;
  final FavoriteColor? favoriteColor;
  final ValueChanged<FavoriteColor?> onFavoriteChanged;
  final VoidCallback? onOpenDetail;
  final LoadWorkSummaryCallback? onLoadSummary;
  final VoidCallback? onDownload;
  final VoidCallback? onOpenDownloads;
  final SearchAuthorCallback? onSearchAuthor;
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
    this.onLoadSummary,
    this.onDownload,
    this.onOpenDownloads,
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
  bool _isLoadingSummary = false;
  bool _summaryLoaded = false;
  late String _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.work.summary.trim();
  }

  @override
  void didUpdateWidget(covariant ExpandableWorkCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.work.ncode != widget.work.ncode) {
      _expanded = false;
      _isLoadingSummary = false;
      _summaryLoaded = false;
      _summary = widget.work.summary.trim();
    }
  }

  List<String> get _tags {
    return widget.work.keyword
        .split(RegExp(r'[\s　]+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  Future<void> _showMoreMenu() async {
    final result = widget.work;
    final tags = _tags;

    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, 'favorite');
              },
              child: const Text('お気に入り登録'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, 'download');
              },
              child: const Text('ダウンロード'),
            ),
            if (widget.hasAnyDownload)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext, 'open_download');
                },
                child: const Text('ダウンロードファイルを開く'),
              ),
            if (widget.hasAnyDownload)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () {
                  Navigator.pop(sheetContext, 'delete_download');
                },
                child: const Text('ダウンロードファイルの削除'),
              ),
            if (widget.hasAnyRead)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () {
                  Navigator.pop(sheetContext, 'delete_read');
                },
                child: const Text('既読の削除(キャッシュも消す)'),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, 'author');
              },
              child: Text('作者:${result.author}'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext, 'tag');
              },
              child: Text('タグ (${tags.length})'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
            },
            child: const Text('キャンセル'),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selected == 'open_download') {
      widget.onOpenDownloads?.call();
      return;
    }
    if (selected == 'favorite') {
      if (widget.favoriteColor == null) {
        widget.onFavoriteChanged(FavoriteColor.blue);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('すでにお気に入りに登録されています')));
      }
    } else if (selected == 'download') {
      widget.onDownload?.call();
    } else if (selected == 'delete_download') {
      widget.onDeleteDownload?.call();
    } else if (selected == 'delete_read') {
      widget.onDeleteRead?.call();
    } else if (selected == 'author') {
      widget.onSearchAuthor?.call(result.author, result.authorId);
    } else if (selected == 'tag') {
      await _showTagMenu(tags);
    }
  }

  Future<void> _showTagMenu(List<String> tags) async {
    if (tags.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タグが登録されていません')));
      return;
    }

    final selectedTag = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) {
        return CupertinoActionSheet(
          actions: [
            for (final tag in tags)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext, tag);
                },
                child: Text(tag),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
            },
            child: const Text('キャンセル'),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selectedTag != null) {
      widget.onSearchTag?.call(selectedTag);
    }
  }

  Future<void> _toggleExpanded() async {
    final willExpand = !_expanded;

    setState(() {
      _expanded = willExpand;
    });

    if (!willExpand || _summaryLoaded || widget.onLoadSummary == null) {
      return;
    }

    final requestedWorkId = widget.work.ncode;

    setState(() {
      _isLoadingSummary = true;
      _summaryLoaded = true;
    });

    try {
      final loadedSummary = (await widget.onLoadSummary!.call()).trim();

      if (!mounted || widget.work.ncode != requestedWorkId) {
        return;
      }

      if (loadedSummary.isNotEmpty) {
        setState(() {
          _summary = loadedSummary;
        });
      }
    } catch (_) {
      // 正式なあらすじを取得できない場合は、
      // 検索結果に含まれる概要をそのまま使用します。
    } finally {
      if (mounted && widget.work.ncode == requestedWorkId) {
        setState(() {
          _isLoadingSummary = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.work;
    final theme = Theme.of(context);
    final isRead = widget.hasAnyRead;
    final summary = _summary.trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleExpanded,
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

                // タイトル・作者・更新日時
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 作品タイトル
                      Text(
                        '[${result.statusLabel}] '
                        '${result.title}',
                        softWrap: true,
                        maxLines: 1000,
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: isRead ? Colors.grey[500] : null,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // 作者・サイト
                      Text(
                        '作:${result.author}　'
                        'サイト:${result.site.displayName}',
                        softWrap: true,
                        maxLines: 1000,
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          height: 1.35,
                          color: isRead ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 2),

                      // 更新日時
                      Text(
                        '更新日:${result.generalLastup}',
                        softWrap: true,
                        maxLines: 1000,
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          height: 1.35,
                          color: isRead ? Colors.grey[600] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                // 右側メニュー・ダウンロード済み表示
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _showMoreMenu,
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

            // カードをタップして展開したときの詳細情報
            if (_expanded) ...[
              const SizedBox(height: 8),

              // あらすじ
              if (_isLoadingSummary)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (summary.isNotEmpty)
                Text(
                  summary,
                  softWrap: true,
                  maxLines: 10000,
                  overflow: TextOverflow.visible,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 1.6,
                    color: isRead ? Colors.grey[600] : null,
                  ),
                )
              else
                Text(
                  'あらすじを取得できませんでした',
                  softWrap: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 1.6,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),

              const SizedBox(height: 8),

              // 文字数・お気に入り人数
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '文字数:${result.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    'お気に入り人数:'
                    '${result.favNovelCnt}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),

              // タグ
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tags.map((tag) {
                    return Text(
                      tag,
                      softWrap: true,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 8),

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
