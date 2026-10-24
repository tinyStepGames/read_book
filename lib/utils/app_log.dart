import 'package:flutter/foundation.dart';

/// デバッグビルド専用の、機密情報を含めないログ出力です。
abstract final class AppLog {
  /// 固定メッセージと例外の型だけを出力します。
  ///
  /// 例外本文、URL、作品ID、話番号、タイトル、ファイルパス、
  /// スタックトレースは出力しません。
  static void failure(String operation, Object error) {
    if (!kDebugMode) {
      return;
    }

    debugPrint('$operation (${error.runtimeType})');
  }
}
