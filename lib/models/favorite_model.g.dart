// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoriteModel _$FavoriteModelFromJson(Map<String, dynamic> json) =>
    FavoriteModel(
      id: json['_id'] as String,
      userId: json['userId'] as String,
      entryId: json['entryId'] as String,
      entry: json['entry'] == null
          ? null
          : DictionaryEntryModel.fromJson(
              json['entry'] as Map<String, dynamic>,
            ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$FavoriteModelToJson(FavoriteModel instance) =>
    <String, dynamic>{
      '_id': instance.id,
      'userId': instance.userId,
      'entryId': instance.entryId,
      'entry': instance.entry,
      'createdAt': instance.createdAt.toIso8601String(),
    };
