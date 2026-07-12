import 'package:hive/hive.dart';

part 'read_mark.g.dart';

@HiveType(typeId: 8)
class ReadMark extends HiveObject {
  @HiveField(0)
  String workId;

  @HiveField(1)
  int episodeNo;

  @HiveField(2)
  DateTime readAt;

  ReadMark({
    required this.workId,
    required this.episodeNo,
    required this.readAt,
  });
}
