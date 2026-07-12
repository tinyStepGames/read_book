import 'package:hive/hive.dart';

part 'download_job.g.dart';

@HiveType(typeId: 6)
class DownloadJob extends HiveObject {
  @HiveField(0)
  String workId;

  @HiveField(1)
  int totalCount;

  @HiveField(2)
  int doneCount;

  @HiveField(3)
  DateTime startedAt;

  @HiveField(4)
  bool isCompleted;

  DownloadJob({
    required this.workId,
    required this.totalCount,
    required this.doneCount,
    required this.startedAt,
    required this.isCompleted,
  });
}
