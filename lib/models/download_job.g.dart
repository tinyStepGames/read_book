// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_job.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadJobAdapter extends TypeAdapter<DownloadJob> {
  @override
  final int typeId = 6;

  @override
  DownloadJob read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadJob(
      workId: fields[0] as String,
      totalCount: fields[1] as int,
      doneCount: fields[2] as int,
      startedAt: fields[3] as DateTime,
      isCompleted: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadJob obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.workId)
      ..writeByte(1)
      ..write(obj.totalCount)
      ..writeByte(2)
      ..write(obj.doneCount)
      ..writeByte(3)
      ..write(obj.startedAt)
      ..writeByte(4)
      ..write(obj.isCompleted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadJobAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
