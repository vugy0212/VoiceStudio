import 'dart:convert';

class SavedAudio {
  final String id;
  final String title;
  final String filePath;
  final double duration;
  final DateTime createdAt;
  final String profileName;
  final String text;
  final bool isFavorite;

  const SavedAudio({
    required this.id,
    required this.title,
    required this.filePath,
    required this.duration,
    required this.createdAt,
    required this.profileName,
    required this.text,
    this.isFavorite = false,
  });

  SavedAudio copyWith({
    String? id,
    String? title,
    String? filePath,
    double? duration,
    DateTime? createdAt,
    String? profileName,
    String? text,
    bool? isFavorite,
  }) {
    return SavedAudio(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      profileName: profileName ?? this.profileName,
      text: text ?? this.text,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'file_path': filePath,
      'duration': duration,
      'created_at': createdAt.toIso8601String(),
      'profile_name': profileName,
      'text': text,
      'is_favorite': isFavorite,
    };
  }

  factory SavedAudio.fromJson(Map<String, dynamic> json) {
    return SavedAudio(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Audio',
      filePath: json['file_path']?.toString() ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      profileName: json['profile_name']?.toString() ?? 'Default',
      text: json['text']?.toString() ?? '',
      isFavorite: json['is_favorite'] == true,
    );
  }

  static List<SavedAudio> decodeList(String raw) {
    try {
      final List list = jsonDecode(raw);
      return list.map((item) => SavedAudio.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<SavedAudio> list) {
    return jsonEncode(list.map((item) => item.toJson()).toList());
  }
}
