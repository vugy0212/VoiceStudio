import 'dart:convert';

class VoiceProfile {
  final String id;
  final String name;
  final String kind;
  final String language;
  final String? refText;
  final String? instruct;
  final String? personality;
  final String? refAudioPath;
  final String? createdAt;
  final String? creatorUserId;
  final String? creatorName;
  final String? creatorEmail;
  final String? creatorAt;

  const VoiceProfile({
    required this.id,
    required this.name,
    this.kind = 'clone',
    this.language = 'Auto',
    this.refText,
    this.instruct,
    this.personality,
    this.refAudioPath,
    this.createdAt,
    this.creatorUserId,
    this.creatorName,
    this.creatorEmail,
    this.creatorAt,
  });

  bool get isUserCreated =>
      creatorUserId != null && creatorUserId!.trim().isNotEmpty;

  VoiceProfile copyWith({
    String? name,
    String? language,
    String? refText,
    String? instruct,
    String? personality,
    String? creatorUserId,
    String? creatorName,
    String? creatorEmail,
    String? creatorAt,
  }) {
    return VoiceProfile(
      id: id,
      name: name ?? this.name,
      kind: kind,
      language: language ?? this.language,
      refText: refText ?? this.refText,
      instruct: instruct ?? this.instruct,
      personality: personality ?? this.personality,
      refAudioPath: refAudioPath,
      createdAt: createdAt,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      creatorName: creatorName ?? this.creatorName,
      creatorEmail: creatorEmail ?? this.creatorEmail,
      creatorAt: creatorAt ?? this.creatorAt,
    );
  }

  factory VoiceProfile.fromJson(Map<String, dynamic> json) {
    final lang = json['language']?.toString().trim() ?? '';
    return VoiceProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Neimenovani glas',
      kind: json['kind']?.toString() ?? 'clone',
      language: lang.isEmpty ? 'Auto' : lang,
      refText: json['ref_text']?.toString(),
      instruct: json['instruct']?.toString(),
      personality: json['personality']?.toString(),
      refAudioPath: json['ref_audio_path']?.toString(),
      createdAt: json['created_at']?.toString(),
      creatorUserId: json['creator_user_id']?.toString(),
      creatorName: json['creator_name']?.toString(),
      creatorEmail: json['creator_email']?.toString(),
      creatorAt: json['creator_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind,
      'language': language,
      if (refText != null) 'ref_text': refText,
      if (instruct != null) 'instruct': instruct,
      if (personality != null) 'personality': personality,
      if (refAudioPath != null) 'ref_audio_path': refAudioPath,
      if (createdAt != null) 'created_at': createdAt,
      if (creatorUserId != null) 'creator_user_id': creatorUserId,
      if (creatorName != null) 'creator_name': creatorName,
      if (creatorEmail != null) 'creator_email': creatorEmail,
      if (creatorAt != null) 'creator_at': creatorAt,
    };
  }

  static String encodeList(List<VoiceProfile> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }

  static List<VoiceProfile> decodeList(String raw) {
    try {
      final List decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => VoiceProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
