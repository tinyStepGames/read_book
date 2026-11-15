import 'package:flutter/material.dart';

/// 書庫のあらすじを、作品詳細と同じ外観の枠内で表示します。
class ArchiveSummaryView extends StatefulWidget {
  final String title;
  final String summary;
  final int previewLines;
  final TextStyle? style;

  const ArchiveSummaryView({
    super.key,
    required this.title,
    required this.summary,
    required this.previewLines,
    this.style,
  }) : assert(previewLines > 0);

  @override
  State<ArchiveSummaryView> createState() => _ArchiveSummaryViewState();
}

class _ArchiveSummaryViewState extends State<ArchiveSummaryView> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant ArchiveSummaryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.summary != widget.summary ||
            oldWidget.title != widget.title) &&
        _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summary.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('archive-summary-frame'),
      constraints: const BoxConstraints(maxHeight: 220),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.black
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: false,
        trackVisibility: false,
        thickness: 6,
        radius: const Radius.circular(8),
        scrollbarOrientation: ScrollbarOrientation.right,
        interactive: true,
        child: SingleChildScrollView(
          key: const ValueKey('archive-inline-summary-scroll'),
          controller: _controller,
          primary: false,
          padding: const EdgeInsets.only(right: 10),
          child: Text(
            widget.summary,
            key: const ValueKey('archive-inline-summary-body'),
            softWrap: true,
            maxLines: null,
            overflow: TextOverflow.visible,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      ),
    );
  }
}
