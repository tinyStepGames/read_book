import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/favorite_color.dart';

// キャンセル(外側タップ含む)を「解除」と区別するための目印
class _CancelMarker {
  const _CancelMarker();
}

const _cancelMarker = _CancelMarker();

// 明示的な「解除」を表す目印
class _ClearMarker {
  const _ClearMarker();
}

const _clearMarker = _ClearMarker();

class FavoriteStarButton extends StatelessWidget {
  final FavoriteColor? currentColor;
  final ValueChanged<FavoriteColor?> onColorSelected;

  const FavoriteStarButton({
    super.key,
    required this.currentColor,
    required this.onColorSelected,
  });

  Future<void> _showColorPicker(BuildContext context) async {
    final result = await showCupertinoModalPopup<Object?>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          for (final color in FavoriteColor.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, color),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    currentColor == color ? Icons.star : Icons.star_border,
                    color: color.materialColor,
                  ),
                  const SizedBox(width: 8),
                  Text(color.label, style: TextStyle(color: color.materialColor)),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, _clearMarker),
            child: const Text('解除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, _cancelMarker),
          child: const Text('キャンセル'),
        ),
      ),
    );

    // 外側タップによる暗黙的なdismiss(null)も「キャンセル」として扱い、何もしない
    if (result == null || result is _CancelMarker) {
      return;
    }
    // 「解除」ボタンが明示的に押された場合のみ星を解除する
    if (result is _ClearMarker) {
      onColorSelected(null);
      return;
    }
    if (result is FavoriteColor && result != currentColor) {
      onColorSelected(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = currentColor != null;
    return GestureDetector(
      onTap: () => onColorSelected(isActive ? null : FavoriteColor.blue),
      onLongPress: () => _showColorPicker(context),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          isActive ? Icons.star : Icons.star_border,
          color: isActive ? currentColor!.materialColor : Colors.grey,
          size: 26,
        ),
      ),
    );
  }
}
