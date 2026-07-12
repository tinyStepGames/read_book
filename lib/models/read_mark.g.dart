// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'read_mark.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReadMarkAdapter extends TypeAdapter<ReadMark> {
  @override
  final int typeId = 8;

  @override
  ReadMark read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReadMark(
      workId: fields[0] as String,
      episodeNo: fields[1] as int,
      readAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ReadMark obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.workId)
      ..writeByte(1)
      ..write(obj.episodeNo)
      ..writeByte(2)
      ..write(obj.readAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadMarkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
