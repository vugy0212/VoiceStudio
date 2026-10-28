import 'dart:convert';

class VoiceGroup {
  final String id;
  final String name;
  final List<String> voiceIds;

  const VoiceGroup({
    required this.id,
    required this.name,
    required this.voiceIds,
  });

  VoiceGroup copyWith({
    String? name,
    List<String>? voiceIds,
  }) {
    return VoiceGroup(
      id: id,
      name: name ?? this.name,
      voiceIds: voiceIds ?? this.voiceIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'voiceIds': voiceIds,
      };

  factory VoiceGroup.fromJson(Map<String, dynamic> json) {
    final rawIds = json['voiceIds'];
    final list = rawIds is List
        ? rawIds.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    return VoiceGroup(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Grupa').toString(),
      voiceIds: list,
    );
  }

  static const List<VoiceGroup> defaultGroups = [
    VoiceGroup(
      id: 'serije_likovi',
      name: 'Glumci & Likovi',
      voiceIds: [
        '7f0c9f12', // pantić
        '615d3946', // Šojić (Ćorka)
        '9ebc541f', // Bata S.
        '044e7ae8', // dijete
        '96643a40', // Dida Šime
        '653d47ca', // Maminjo
      ],
    ),
    VoiceGroup(
      id: 'politika',
      name: 'Političari',
      voiceIds: [
        '87f3574f', // plenky
        '70f9c92a', // Zoki
        'f8015a6c', // Kerum
        '67532578', // Longin
        '088ed5e0', // aleksandar vučić
        '9a65eb20', // A Vulin
        '9593bd2a', // Šešelj
        '25338cf2', // Dodik M
      ],
    ),
  ];
}

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String role; // 'admin' | 'premium' | 'user'
  final bool approved;
  final bool blocked;
  final int dailyQuota;
  final int usedToday;
  final String lastUsageDate; // YYYY-MM-DD
  final String sessionToken;
  final String createdAt;
  final String voiceGroupId; // '' (default per role), 'custom' (per-user selection), or a VoiceGroup.id
  final List<String> customVoiceIds; // explicit voice IDs when voiceGroupId == 'custom' or group snapshot

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.approved,
    required this.blocked,
    required this.dailyQuota,
    required this.usedToday,
    required this.lastUsageDate,
    required this.sessionToken,
    required this.createdAt,
    this.voiceGroupId = '',
    this.customVoiceIds = const [],
  });

  bool get isAdmin => role == 'admin';
  bool get isPremium => role == 'premium' || role == 'admin';
  bool get hasCustomVoiceSelection =>
      !isAdmin && (voiceGroupId.isNotEmpty || customVoiceIds.isNotEmpty);
  bool get hasAllVoicesAccess =>
      isAdmin || (isPremium && !hasCustomVoiceSelection);

  bool get canUseApp => approved && !blocked;

  int get effectiveUsedToday {
    final today = _todayIso();
    return lastUsageDate == today ? usedToday : 0;
  }

  int get remainingQuota {
    if (isAdmin) return 999999;
    return (dailyQuota - effectiveUsedToday).clamp(0, dailyQuota);
  }

  bool get hasQuotaLeft => isAdmin || remainingQuota > 0;

  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  AppUser copyWith({
    String? displayName,
    String? role,
    bool? approved,
    bool? blocked,
    int? dailyQuota,
    int? usedToday,
    String? lastUsageDate,
    String? sessionToken,
    String? voiceGroupId,
    List<String>? customVoiceIds,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      approved: approved ?? this.approved,
      blocked: blocked ?? this.blocked,
      dailyQuota: dailyQuota ?? this.dailyQuota,
      usedToday: usedToday ?? this.usedToday,
      lastUsageDate: lastUsageDate ?? this.lastUsageDate,
      sessionToken: sessionToken ?? this.sessionToken,
      createdAt: createdAt,
      voiceGroupId: voiceGroupId ?? this.voiceGroupId,
      customVoiceIds: customVoiceIds ?? this.customVoiceIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'role': role,
        'approved': approved,
        'blocked': blocked,
        'dailyQuota': dailyQuota,
        'usedToday': usedToday,
        'lastUsageDate': lastUsageDate,
        'sessionToken': sessionToken,
        'createdAt': createdAt,
        'voiceGroupId': voiceGroupId,
        'customVoiceIds': customVoiceIds,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawCustom = json['customVoiceIds'];
    final customList = rawCustom is List
        ? rawCustom.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    return AppUser(
      uid: (json['uid'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      approved: json['approved'] == true,
      blocked: json['blocked'] == true,
      dailyQuota: int.tryParse((json['dailyQuota'] ?? '30').toString()) ?? 30,
      usedToday: int.tryParse((json['usedToday'] ?? '0').toString()) ?? 0,
      lastUsageDate: (json['lastUsageDate'] ?? '').toString(),
      sessionToken: (json['sessionToken'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      voiceGroupId: (json['voiceGroupId'] ?? '').toString(),
      customVoiceIds: customList,
    );
  }

  String encode() => jsonEncode(toJson());
  static AppUser decode(String raw) =>
      AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

class HubConnectionConfig {
  // Default 4 allowed public voices for standard (demo) users: Pantić, Šojić (Ćorka), dijete, Bata S.
  static const List<String> defaultAllowedVoiceIds = [
    '7f0c9f12', // pantić
    '615d3946', // Šojić (Ćorka)
    '044e7ae8', // dijete
    '9ebc541f', // Bata S.
  ];

  final String remoteUrl;
  final String localUrl;
  final String cfClientId;
  final String cfClientSecret;
  final bool autoApproveNewUsers;
  final int defaultDailyQuota;
  final String adminEmail;
  final List<String> allowedVoiceIds;
  final List<VoiceGroup> voiceGroups;

  const HubConnectionConfig({
    required this.remoteUrl,
    required this.localUrl,
    required this.cfClientId,
    required this.cfClientSecret,
    this.autoApproveNewUsers = false,
    this.defaultDailyQuota = 30,
    this.adminEmail = 'vugy0212@gmail.com',
    this.allowedVoiceIds = defaultAllowedVoiceIds,
    this.voiceGroups = VoiceGroup.defaultGroups,
  });

  HubConnectionConfig copyWith({
    String? remoteUrl,
    String? localUrl,
    String? cfClientId,
    String? cfClientSecret,
    bool? autoApproveNewUsers,
    int? defaultDailyQuota,
    String? adminEmail,
    List<String>? allowedVoiceIds,
    List<VoiceGroup>? voiceGroups,
  }) {
    return HubConnectionConfig(
      remoteUrl: remoteUrl ?? this.remoteUrl,
      localUrl: localUrl ?? this.localUrl,
      cfClientId: cfClientId ?? this.cfClientId,
      cfClientSecret: cfClientSecret ?? this.cfClientSecret,
      autoApproveNewUsers: autoApproveNewUsers ?? this.autoApproveNewUsers,
      defaultDailyQuota: defaultDailyQuota ?? this.defaultDailyQuota,
      adminEmail: adminEmail ?? this.adminEmail,
      allowedVoiceIds: allowedVoiceIds ?? this.allowedVoiceIds,
      voiceGroups: voiceGroups ?? this.voiceGroups,
    );
  }
}

class InviteCodeItem {
  final String code;
  final String note;
  final String role; // 'user' (Demo) | 'premium' (Premium)
  final String voiceGroupId;
  final List<String> customVoiceIds;
  final int dailyQuota;
  final int maxUses;
  final int usedCount;
  final String createdAt;

  const InviteCodeItem({
    required this.code,
    required this.note,
    this.role = 'user',
    this.voiceGroupId = '',
    this.customVoiceIds = const [],
    required this.dailyQuota,
    required this.maxUses,
    required this.usedCount,
    required this.createdAt,
  });

  bool get isPremiumInvite => role == 'premium';
  bool get isValid => usedCount < maxUses;
}
