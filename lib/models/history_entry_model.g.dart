// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_entry_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HistoryEntryModel _$HistoryEntryModelFromJson(Map<String, dynamic> json) =>
    HistoryEntryModel(
      id: json['_id'] as String,
      userId: json['userId'] as String,
      entryId: json['entryId'] as String,
      entry: json['entry'] == null
          ? null
          : DictionaryEntryModel.fromJson(
              json['entry'] as Map<String, dynamic>,
            ),
      viewedAt: DateTime.parse(json['viewedAt'] as String),
    );

Map<String, dynamic> _$HistoryEntryModelToJson(HistoryEntryModel instance) =>
    <String, dynamic>{
      '_id': instance.id,
      'userId': instance.userId,
      'entryId': instance.entryId,
      'entry': instance.entry,
      'viewedAt': instance.viewedAt.toIso8601String(),
    };
