import 'package:html/dom.dart';

/// 目次から取得する、表示用日時とは独立した改稿情報です。
///
/// 日時を取得・検証できない場合は空文字を返します。
/// 公開日や端末の現在時刻で補完しません。
abstract final class EpisodeSourceMetadata {
  /// なろうの目次内にある「日時 改稿」のtitle属性を読み取ります。
  ///
  /// サイト表示日時を日本標準時として扱い、UTCへ変換します。
  static String narouUpdatedAt(Element? updateElement) {
    if (updateElement == null) {
      return '';
    }

    final pattern = RegExp(
      r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+'
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s+改稿$',
    );
    final candidates = <String>{};

    for (final element in updateElement.querySelectorAll('[title]')) {
      final title = element.attributes['title']?.trim() ?? '';
      final match = pattern.firstMatch(title);

      if (match == null) {
        continue;
      }

      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final minute = int.parse(match.group(5)!);
      final second = int.parse(match.group(6) ?? '0');

      if (year < 1900 || year > 9999) {
        continue;
      }

      final localComponents = DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
      );

      // DateTimeによる無効日付・時刻の繰り上げを受け入れません。
      if (localComponents.year != year ||
          localComponents.month != month ||
          localComponents.day != day ||
          localComponents.hour != hour ||
          localComponents.minute != minute ||
          localComponents.second != second) {
        continue;
      }

      candidates.add(
        localComponents.subtract(const Duration(hours: 9)).toIso8601String(),
      );
    }

    // 相反する複数の改稿日時がある場合も推測しません。
    return candidates.length == 1 ? candidates.single : '';
  }

  /// カクヨム各話のedited_at（Unix秒）をUTCへ変換します。
  ///
  /// 秒の精度を保ち、端末のタイムゾーンに依存させません。
  static String kakuyomuUpdatedAt(Object? value) {
    int? seconds;

    if (value is int) {
      seconds = value;
    } else if (value is String && RegExp(r'^[0-9]+$').hasMatch(value.trim())) {
      seconds = int.tryParse(value.trim());
    }

    // 9999-12-31T23:59:59Zまで。桁違いのミリ秒等は受け入れません。
    if (seconds == null || seconds <= 0 || seconds > 253402300799) {
      return '';
    }

    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toIso8601String();
  }
}
