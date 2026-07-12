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

  Download({
    required this.workId,
    required this.episodeNo,
    required this.episodeTitle,
    required this.body,
    required this.downloadedAt,
    this.publishedAt = '',
  });
}
