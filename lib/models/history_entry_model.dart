import 'package:json_annotation/json_annotation.dart';

import 'dictionary_entry_model.dart';

part 'history_entry_model.g.dart';

@JsonSerializable()
class HistoryEntryModel {
  @JsonKey(name: '_id')
  final String id;
  final String userId;
  final String entryId;
  final DictionaryEntryModel? entry;
  final DateTime viewedAt;

  HistoryEntryModel({
    required this.id,
    required this.userId,
    required this.entryId,
    this.entry,
    required this.viewedAt,
  });

  factory HistoryEntryModel.fromJson(Map<String, dynamic> json) =>
      _$HistoryEntryModelFromJson({
        ...json,
        '_id': json['_id'] ?? json['id'],
        'entryId': json['entryId'] is Map
            ? json['entryId']['_id']
            : json['entryId'],
        'entry':
            json['entry'] ?? (json['entryId'] is Map ? json['entryId'] : null),
      });

  Map<String, dynamic> toJson() => _$HistoryEntryModelToJson(this);
}
