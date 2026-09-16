class GenerationHistory {
  final String id;
  final String text;
  final String filename;
  final double duration;
  final String? createdAt;
  final bool starred;
  final double? speed;
  final String? profileName;

  const GenerationHistory({
    required this.id,
    required this.text,
    required this.filename,
    this.duration = 0.0,
    this.createdAt,
    this.starred = false,
    this.speed,
    this.profileName,
  });

  factory GenerationHistory.fromJson(Map<String, dynamic> json) {
    return GenerationHistory(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      filename: json['filename']?.toString() ?? json['audio_path']?.toString() ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at']?.toString() ?? json['timestamp']?.toString(),
      starred: json['starred'] == true,
      speed: (json['speed'] as num?)?.toDouble(),
      profileName: json['profile_name']?.toString(),
    );
  }
}
