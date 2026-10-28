import 'dart:convert';

class VoiceProfile {
  final String id;
  final String name;
  final String kind;
  final String? instruct;
  final String? refAudioPath;
  final String? createdAt;

  const VoiceProfile({
    required this.id,
    required this.name,
    this.kind = 'clone',
    this.instruct,
    this.refAudioPath,
    this.createdAt,
  });

  factory VoiceProfile.fromJson(Map<String, dynamic> json) {
    return VoiceProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Neimenovani glas',
      kind: json['kind']?.toString() ?? 'clone',
      instruct: json['instruct']?.toString(),
      refAudioPath: json['ref_audio_path']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind,
      if (instruct != null) 'instruct': instruct,
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
