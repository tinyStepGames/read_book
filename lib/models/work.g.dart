// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'work.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkAdapter extends TypeAdapter<Work> {
  @override
  final int typeId = 1;

  @override
  Work read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Work(
      workId: fields[0] as String,
      siteIndex: fields[1] as int,
      title: fields[2] as String,
      author: fields[3] as String,
      genre: fields[4] as String,
      summary: fields[5] as String,
      totalEpisodeCount: fields[6] as int,
      checkedEpisodeCount: fields[7] as int,
      lastUpdatedAt: fields[8] as DateTime,
      isCompleted: fields[9] as bool,
      firstOpenedAt: fields[10] as DateTime?,
      authorId: fields[11] as String?,
      keyword: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Work obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.workId)
      ..writeByte(1)
      ..write(obj.siteIndex)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.author)
      ..writeByte(4)
      ..write(obj.genre)
      ..writeByte(5)
      ..write(obj.summary)
      ..writeByte(6)
      ..write(obj.totalEpisodeCount)
      ..writeByte(7)
      ..write(obj.checkedEpisodeCount)
      ..writeByte(8)
      ..write(obj.lastUpdatedAt)
      ..writeByte(9)
      ..write(obj.isCompleted)
      ..writeByte(10)
      ..write(obj.firstOpenedAt)
      ..writeByte(11)
      ..write(obj.authorId)
      ..writeByte(12)
      ..write(obj.keyword);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
