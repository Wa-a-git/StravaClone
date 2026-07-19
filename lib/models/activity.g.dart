// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ActivityAdapter extends TypeAdapter<Activity> {
  @override
  final int typeId = 0;

  @override
  Activity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Activity(
      date: fields[0] as DateTime,
      distance: fields[1] as double,
      duration: fields[2] as int,
      route: (fields[3] as List)
          .map((dynamic e) => (e as List).cast<double>())
          .toList(),
      name: fields[4] as String?,
      pauseDurationSeconds: fields[5] as int,
      lapCount: fields[6] as int,
      laps: (fields[7] as List?)?.cast<dynamic>(),
      elevations: (fields[8] as List?)?.cast<double>(),
      workoutType: fields[9] as String?,
      pointSeconds: (fields[10] as List?)?.cast<int>(),
      inclinePercent: fields[11] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, Activity obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.distance)
      ..writeByte(2)
      ..write(obj.duration)
      ..writeByte(3)
      ..write(obj.route)
      ..writeByte(4)
      ..write(obj.name)
      ..writeByte(5)
      ..write(obj.pauseDurationSeconds)
      ..writeByte(6)
      ..write(obj.lapCount)
      ..writeByte(7)
      ..write(obj.laps)
      ..writeByte(8)
      ..write(obj.elevations)
      ..writeByte(9)
      ..write(obj.workoutType)
      ..writeByte(10)
      ..write(obj.pointSeconds)
      ..writeByte(11)
      ..write(obj.inclinePercent);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
