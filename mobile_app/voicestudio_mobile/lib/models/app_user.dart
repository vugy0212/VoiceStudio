import 'dart:convert';

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
  });

  bool get isAdmin => role == 'admin';
  bool get isPremium => role == 'premium' || role == 'admin';
  bool get hasAllVoicesAccess => isAdmin || isPremium;

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
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
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
    );
  }

  String encode() => jsonEncode(toJson());
  static AppUser decode(String raw) => AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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

  const HubConnectionConfig({
    required this.remoteUrl,
    required this.localUrl,
    required this.cfClientId,
    required this.cfClientSecret,
    this.autoApproveNewUsers = false,
    this.defaultDailyQuota = 30,
    this.adminEmail = 'vugy0212@gmail.com',
    this.allowedVoiceIds = defaultAllowedVoiceIds,
  });
}

class InviteCodeItem {
  final String code;
  final String note;
  final String role; // 'user' (Demo) | 'premium' (Premium)
  final int dailyQuota;
  final int maxUses;
  final int usedCount;
  final String createdAt;

  const InviteCodeItem({
    required this.code,
    required this.note,
    this.role = 'user',
    required this.dailyQuota,
    required this.maxUses,
    required this.usedCount,
    required this.createdAt,
  });

  bool get isPremiumInvite => role == 'premium';
  bool get isValid => usedCount < maxUses;
}
