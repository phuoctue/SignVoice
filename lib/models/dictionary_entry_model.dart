import 'package:json_annotation/json_annotation.dart';

part 'dictionary_entry_model.g.dart';

/// Entry status
enum EntryStatus {
  @JsonValue('DRAFT')
  draft,
  @JsonValue('PUBLISHED')
  published,
  @JsonValue('ARCHIVED')
  archived,
}

/// Difficulty level
enum DifficultyLevel {
  @JsonValue('BEGINNER')
  beginner,
  @JsonValue('INTERMEDIATE')
  intermediate,
  @JsonValue('ADVANCED')
  advanced,
}

/// Related word relationship type
enum RelationshipType {
  @JsonValue('SYNONYM')
  synonym,
  @JsonValue('ANTONYM')
  antonym,
  @JsonValue('RELATED')
  related,
  @JsonValue('SEE_ALSO')
  seeAlso,
}

/// Related word reference
@JsonSerializable()
class RelatedWord {
  final String entryId;
  final RelationshipType relationshipType;

  RelatedWord({required this.entryId, required this.relationshipType});

  factory RelatedWord.fromJson(Map<String, dynamic> json) =>
      _$RelatedWordFromJson(json);

  Map<String, dynamic> toJson() => _$RelatedWordToJson(this);
}

/// Dictionary entry model
@JsonSerializable()
class DictionaryEntryModel {
  @JsonKey(name: '_id')
  final String id;

  final String word;
  final String definition;

  final String videoUrl;
  final String? thumbnailUrl;
  final List<String>? imageUrls;

  final String categoryId;
  final List<String>? tags;
  final DifficultyLevel? difficulty;

  final String? usageExample;
  final String? notes;
  final List<RelatedWord>? relatedWords;

  final EntryStatus status;
  final String? rejectionReason;

  final int viewCount;
  final int favoriteCount;

  final String createdBy;
  final String? lastModifiedBy;
  final DateTime? publishedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  DictionaryEntryModel({
    required this.id,
    required this.word,
    required this.definition,
    required this.videoUrl,
    this.thumbnailUrl,
    this.imageUrls,
    required this.categoryId,
    this.tags,
    this.difficulty,
    this.usageExample,
    this.notes,
    this.relatedWords,
    required this.status,
    this.rejectionReason,
    required this.viewCount,
    required this.favoriteCount,
    required this.createdBy,
    this.lastModifiedBy,
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DictionaryEntryModel.fromJson(Map<String, dynamic> json) =>
      _$DictionaryEntryModelFromJson({
        ...json,
        for (final key in ['categoryId', 'createdBy', 'lastModifiedBy'])
          key: json[key] is Map ? json[key]['_id'] : json[key],
      });

  Map<String, dynamic> toJson() => _$DictionaryEntryModelToJson(this);

  /// Check if entry is published
  bool get isPublished => status == EntryStatus.published;

  /// Get difficulty label
  String? get difficultyLabel {
    switch (difficulty) {
      case DifficultyLevel.beginner:
        return 'Beginner';
      case DifficultyLevel.intermediate:
        return 'Intermediate';
      case DifficultyLevel.advanced:
        return 'Advanced';
      case null:
        return null;
    }
  }

  /// Copy with method
  DictionaryEntryModel copyWith({
    String? id,
    String? word,
    String? definition,
    String? videoUrl,
    String? thumbnailUrl,
    List<String>? imageUrls,
    String? categoryId,
    List<String>? tags,
    DifficultyLevel? difficulty,
    String? usageExample,
    String? notes,
    List<RelatedWord>? relatedWords,
    EntryStatus? status,
    String? rejectionReason,
    int? viewCount,
    int? favoriteCount,
    String? createdBy,
    String? lastModifiedBy,
    DateTime? publishedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DictionaryEntryModel(
      id: id ?? this.id,
      word: word ?? this.word,
      definition: definition ?? this.definition,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      categoryId: categoryId ?? this.categoryId,
      tags: tags ?? this.tags,
      difficulty: difficulty ?? this.difficulty,
      usageExample: usageExample ?? this.usageExample,
      notes: notes ?? this.notes,
      relatedWords: relatedWords ?? this.relatedWords,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      viewCount: viewCount ?? this.viewCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      createdBy: createdBy ?? this.createdBy,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
