import 'package:hive/hive.dart';

part 'download.g.dart';

@HiveType(typeId: 7)
class Download extends HiveObject {
  @HiveField(0)
  String workId;

  @HiveField(1)
  int episodeNo;

  @HiveField(2)
  String episodeTitle;

  @HiveField(3)
  String body;

  @HiveField(4)
  DateTime downloadedAt;

  /// 作品サイト上での掲載日時
  @HiveField(5, defaultValue: '')
  String publishedAt;

  /// サイト側で各話を一意に識別する値です。
  ///
  /// カクヨムではepisodeId、小説家になろうでは話URLを保存します。
  /// 既存データでは空文字です。
  @HiveField(6, defaultValue: '')
  String sourceId;

  /// サイト側で確認できた各話の最終更新情報です。
  ///
  /// 本文改稿の再取得判定に使用します。
  /// 既存データや更新情報を取得できない場合は空文字です。
  @HiveField(7, defaultValue: '')
  String sourceUpdatedAt;

  Download({
    required this.workId,
    required this.episodeNo,
    required this.episodeTitle,
    required this.body,
    required this.downloadedAt,
    this.publishedAt = '',
    this.sourceId = '',
    this.sourceUpdatedAt = '',
  });
}
