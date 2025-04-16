import 'package:cloud_firestore/cloud_firestore.dart';

enum StoryType {
  text,
  image,
  video
}

class Story {
  final String id;
  final String authorId;
  final String? authorName;
  final String? authorPhotoUrl;
  final StoryType type;
  final String? text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime expiresAt; // История истекает через 24 часа
  final List<String> viewedBy; // ID пользователей, просмотревших историю
  final String? familyTreeId; // ID семейного дерева, для которого создана история
  final bool isPublic; // Доступна всем или только членам дерева

  Story({
    required this.id,
    required this.authorId,
    this.authorName,
    this.authorPhotoUrl,
    required this.type,
    this.text,
    this.mediaUrl,
    this.thumbnailUrl,
    required this.createdAt,
    required this.expiresAt,
    this.viewedBy = const [],
    this.familyTreeId,
    this.isPublic = false,
  });

  factory Story.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Story(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'],
      authorPhotoUrl: data['authorPhotoUrl'],
      type: _stringToStoryType(data['type'] ?? 'text'),
      text: data['text'],
      mediaUrl: data['mediaUrl'],
      thumbnailUrl: data['thumbnailUrl'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      viewedBy: data['viewedBy'] != null 
          ? List<String>.from(data['viewedBy']) 
          : [],
      familyTreeId: data['familyTreeId'],
      isPublic: data['isPublic'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'type': _storyTypeToString(type),
      'text': text,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewedBy': viewedBy,
      'familyTreeId': familyTreeId,
      'isPublic': isPublic,
    };
  }
  
  // Проверка, просмотрел ли пользователь историю
  bool isViewedBy(String userId) {
    return viewedBy.contains(userId);
  }
  
  // Проверка, истекла ли история
  bool isExpired() {
    return DateTime.now().isAfter(expiresAt);
  }
  
  // Преобразование строки в тип истории
  static StoryType _stringToStoryType(String value) {
    switch (value) {
      case 'image': return StoryType.image;
      case 'video': return StoryType.video;
      default: return StoryType.text;
    }
  }
  
  // Преобразование типа истории в строку
  static String _storyTypeToString(StoryType type) {
    switch (type) {
      case StoryType.image: return 'image';
      case StoryType.video: return 'video';
      case StoryType.text: return 'text';
    }
  }
} 