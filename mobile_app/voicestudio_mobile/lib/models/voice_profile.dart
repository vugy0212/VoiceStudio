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
  });

  VoiceProfile copyWith({
    String? name,
    String? language,
    String? refText,
    String? instruct,
    String? personality,
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
