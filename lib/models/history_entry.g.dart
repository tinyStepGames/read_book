// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HistoryEntryAdapter extends TypeAdapter<HistoryEntry> {
  @override
  final int typeId = 5;

  @override
  HistoryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HistoryEntry(
      workId: fields[0] as String,
      episodeNo: fields[1] as int,
      scrollFraction: fields[2] as double,
      lastReadAt: fields[3] as DateTime,
      episodeTitle: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, HistoryEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.workId)
      ..writeByte(1)
      ..write(obj.episodeNo)
      ..writeByte(2)
      ..write(obj.scrollFraction)
      ..writeByte(3)
      ..write(obj.lastReadAt)
      ..writeByte(4)
      ..write(obj.episodeTitle);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
