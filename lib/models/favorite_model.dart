import 'package:json_annotation/json_annotation.dart';

import 'dictionary_entry_model.dart';

part 'favorite_model.g.dart';

@JsonSerializable()
class FavoriteModel {
  @JsonKey(name: '_id')
  final String id;
  final String userId;
  final String entryId;
  final DictionaryEntryModel? entry;
  final DateTime createdAt;

  FavoriteModel({
    required this.id,
    required this.userId,
    required this.entryId,
    this.entry,
    required this.createdAt,
  });

  factory FavoriteModel.fromJson(Map<String, dynamic> json) =>
      _$FavoriteModelFromJson({
        ...json,
        '_id': json['_id'] ?? json['id'],
        'entryId': json['entryId'] is Map
            ? json['entryId']['_id']
            : json['entryId'],
        'entry':
            json['entry'] ?? (json['entryId'] is Map ? json['entryId'] : null),
      });

  Map<String, dynamic> toJson() => _$FavoriteModelToJson(this);
}
