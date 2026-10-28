import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../config/constants.dart';
import '../models/app_user.dart';

class FirebaseHubService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl:
          'https://firestore.googleapis.com/v1/projects/${AppConstants.firebaseProjectId}/databases/(default)/documents',
      queryParameters: {'key': AppConstants.firebaseApiKey},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  static String _uidFromEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final digest = sha256.convert(utf8.encode('vs_uid:$normalized')).toString();
    return 'u_${digest.substring(0, 20)}';
  }

  static String _hashPassword(String email, String password) {
    final normalized = email.trim().toLowerCase();
    return sha256
        .convert(utf8.encode('vs_pwd_v1:$normalized:${password.trim()}'))
        .toString();
  }

  static String _generateSessionToken(String uid, String role) {
    final digest = sha256
        .convert(utf8.encode('vs_tok_v1:$uid:$role:${AppConstants.firebaseProjectId}'))
        .toString();
    return 'vst_${uid}_${digest.substring(0, 24)}';
  }

  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _strField(Map<String, dynamic> fields, String key, [String fallback = '']) {
    final f = fields[key];
    if (f is Map && f.containsKey('stringValue')) {
      return (f['stringValue'] ?? fallback).toString();
    }
    return fallback;
  }

  static bool _boolField(Map<String, dynamic> fields, String key, [bool fallback = false]) {
    final f = fields[key];
    if (f is Map && f.containsKey('booleanValue')) {
      return f['booleanValue'] == true;
    }
    return fallback;
  }

  static int _intField(Map<String, dynamic> fields, String key, [int fallback = 0]) {
    final f = fields[key];
    if (f is Map) {
      if (f.containsKey('integerValue')) {
        return int.tryParse(f['integerValue'].toString()) ?? fallback;
      }
      if (f.containsKey('stringValue')) {
        return int.tryParse(f['stringValue'].toString()) ?? fallback;
      }
    }
    return fallback;
  }

  static List<String> _strListField(
    Map<String, dynamic> fields,
    String key,
    List<String> fallback,
  ) {
    final f = fields[key];
    if (f is Map && f.containsKey('arrayValue')) {
      final arr = f['arrayValue'];
      if (arr is Map && arr['values'] is List) {
        final values = (arr['values'] as List)
            .map((v) => v is Map ? (v['stringValue'] ?? '').toString() : '')
            .where((s) => s.isNotEmpty)
            .toList();
        if (values.isNotEmpty) return values;
      }
    }
    return fallback;
  }

  static AppUser _userFromFirestoreDoc(Map<String, dynamic> doc) {
    final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};
    final uid = _strField(fields, 'uid');
    final role = _strField(fields, 'role', 'user');
    return AppUser(
      uid: uid,
      email: _strField(fields, 'email'),
      displayName: _strField(fields, 'displayName', 'Korisnik'),
      role: role,
      approved: _boolField(fields, 'approved', false),
      blocked: _boolField(fields, 'blocked', false),
      dailyQuota: _intField(fields, 'dailyQuota', 30),
      usedToday: _intField(fields, 'usedToday', 0),
      lastUsageDate: _strField(fields, 'lastUsageDate', _todayIso()),
      sessionToken: _strField(fields, 'sessionToken', _generateSessionToken(uid, role)),
      createdAt: _strField(fields, 'createdAt', _todayIso()),
    );
  }

  static Map<String, dynamic> _userToFirestoreFields(AppUser user, {String? passwordHash}) {
    final map = <String, dynamic>{
      'uid': {'stringValue': user.uid},
      'email': {'stringValue': user.email},
      'displayName': {'stringValue': user.displayName},
      'role': {'stringValue': user.role},
      'approved': {'booleanValue': user.approved},
      'blocked': {'booleanValue': user.blocked},
      'dailyQuota': {'integerValue': user.dailyQuota.toString()},
      'usedToday': {'integerValue': user.usedToday.toString()},
      'lastUsageDate': {'stringValue': user.lastUsageDate},
      'sessionToken': {'stringValue': user.sessionToken},
      'createdAt': {'stringValue': user.createdAt},
    };
    if (passwordHash != null) {
      map['passwordHash'] = {'stringValue': passwordHash};
    }
    return {'fields': map};
  }

  Future<HubConnectionConfig> fetchConnectionConfig() async {
    final res = await _dio.get('/config/connection');
    final data = res.data as Map<String, dynamic>;
    final fields = (data['fields'] as Map<String, dynamic>?) ?? {};
    return HubConnectionConfig(
      remoteUrl: _strField(fields, 'remoteUrl'),
      localUrl: _strField(fields, 'localUrl'),
      cfClientId: _strField(fields, 'cfClientId'),
      cfClientSecret: _strField(fields, 'cfClientSecret'),
      autoApproveNewUsers: _boolField(fields, 'autoApproveNewUsers', false),
      defaultDailyQuota: _intField(fields, 'defaultDailyQuota', 30),
      adminEmail: _strField(fields, 'adminEmail', AppConstants.adminOwnerEmail),
      allowedVoiceIds: _strListField(
        fields,
        'allowedVoiceIds',
        HubConnectionConfig.defaultAllowedVoiceIds,
      ),
    );
  }

  Future<void> saveConnectionConfig(HubConnectionConfig config) async {
    await _dio.patch(
      '/config/connection',
      data: {
        'fields': {
          'remoteUrl': {'stringValue': config.remoteUrl.trim()},
          'localUrl': {'stringValue': config.localUrl.trim()},
          'cfClientId': {'stringValue': config.cfClientId.trim()},
          'cfClientSecret': {'stringValue': config.cfClientSecret.trim()},
          'autoApproveNewUsers': {'booleanValue': config.autoApproveNewUsers},
          'defaultDailyQuota': {'integerValue': config.defaultDailyQuota.toString()},
          'adminEmail': {'stringValue': config.adminEmail.trim()},
          'allowedVoiceIds': {
            'arrayValue': {
              'values': config.allowedVoiceIds
                  .map((id) => {'stringValue': id})
                  .toList(),
            },
          },
        },
      },
    );
  }

  Future<AppUser> loginWithEmailPassword(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Unesite ispravnu e-mail adresu.');
    }
    if (password.trim().length < 4) {
      throw Exception('Lozinka mora imati najmanje 4 znaka.');
    }

    final uid = _uidFromEmail(cleanEmail);
    final pwdHash = _hashPassword(cleanEmail, password);

    try {
      final res = await _dio.get('/users/$uid');
      final doc = res.data as Map<String, dynamic>;
      final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};
      final storedHash = _strField(fields, 'passwordHash');

      if (storedHash.isNotEmpty && storedHash != pwdHash) {
        throw Exception('Pogrešna lozinka za ovaj račun.');
      }

      final user = _userFromFirestoreDoc(doc);
      if (user.blocked) {
        throw Exception('Vaš korisnički račun je blokiran od strane administratora.');
      }
      return user;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        if (cleanEmail == AppConstants.adminOwnerEmail.toLowerCase()) {
          return registerUser(
            displayName: 'Administrator (Vlasnik)',
            email: cleanEmail,
            password: password,
          );
        }
        throw Exception('Korisnički račun ne postoji. Odaberite "Registracija".');
      }
      throw Exception('Greška pri povezivanju s Firebase poslužiteljem.');
    }
  }

  Future<AppUser> registerUser({
    required String displayName,
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim().isEmpty ? cleanEmail.split('@').first : displayName.trim();

    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Unesite ispravnu e-mail adresu.');
    }
    if (password.trim().length < 4) {
      throw Exception('Lozinka mora imati najmanje 4 znaka.');
    }

    final uid = _uidFromEmail(cleanEmail);

    try {
      final existing = await _dio.get('/users/$uid');
      if (existing.statusCode == 200) {
        throw Exception('Račun s ovom e-mail adresom već postoji. Prijavite se.');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }

    final config = await fetchConnectionConfig();
    final isOwner = cleanEmail == AppConstants.adminOwnerEmail.toLowerCase() ||
        cleanEmail == config.adminEmail.toLowerCase();

    bool approved = isOwner || config.autoApproveNewUsers;
    int quota = isOwner ? 999999 : config.defaultDailyQuota;
    String assignedRole = isOwner ? 'admin' : 'user';

    if (inviteCode != null && inviteCode.trim().isNotEmpty) {
      final cleanCode = inviteCode.trim().toUpperCase();
      final invite = await _consumeInviteCode(cleanCode);
      approved = true;
      quota = invite.dailyQuota;
      if (!isOwner && invite.role == 'premium') {
        assignedRole = 'premium';
      }
    }

    final pwdHash = _hashPassword(cleanEmail, password);
    final newUser = AppUser(
      uid: uid,
      email: cleanEmail,
      displayName: cleanName,
      role: assignedRole,
      approved: approved,
      blocked: false,
      dailyQuota: quota,
      usedToday: 0,
      lastUsageDate: _todayIso(),
      sessionToken: _generateSessionToken(uid, assignedRole),
      createdAt: _todayIso(),
    );

    await _dio.patch(
      '/users/$uid',
      data: _userToFirestoreFields(newUser, passwordHash: pwdHash),
    );

    return newUser;
  }

  Future<AppUser> redeemInviteCodeLogin({
    required String inviteCode,
    required String displayName,
  }) async {
    final cleanCode = inviteCode.trim().toUpperCase();
    final cleanName = displayName.trim();
    if (cleanCode.isEmpty) {
      throw Exception('Unesite pristupni kod (npr. VS-XXXX).');
    }
    if (cleanName.isEmpty) {
      throw Exception('Unesite svoje ime ili nadimak.');
    }

    final invite = await _consumeInviteCode(cleanCode);
    final syntheticEmail =
        '${cleanName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}.${cleanCode.toLowerCase()}@invite.voicestudio';
    final uid = _uidFromEmail(syntheticEmail);
    final assignedRole = invite.role == 'premium' ? 'premium' : 'user';

    final newUser = AppUser(
      uid: uid,
      email: syntheticEmail,
      displayName: cleanName,
      role: assignedRole,
      approved: true,
      blocked: false,
      dailyQuota: invite.dailyQuota,
      usedToday: 0,
      lastUsageDate: _todayIso(),
      sessionToken: _generateSessionToken(uid, assignedRole),
      createdAt: _todayIso(),
    );

    await _dio.patch(
      '/users/$uid',
      data: _userToFirestoreFields(
        newUser,
        passwordHash: _hashPassword(syntheticEmail, cleanCode),
      ),
    );

    return newUser;
  }

  Future<InviteCodeItem> _consumeInviteCode(String cleanCode) async {
    try {
      final res = await _dio.get('/invites/$cleanCode');
      final doc = res.data as Map<String, dynamic>;
      final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};
      final invite = InviteCodeItem(
        code: _strField(fields, 'code', cleanCode),
        note: _strField(fields, 'note'),
        role: _strField(fields, 'role', 'user'),
        dailyQuota: _intField(fields, 'dailyQuota', 30),
        maxUses: _intField(fields, 'maxUses', 1),
        usedCount: _intField(fields, 'usedCount', 0),
        createdAt: _strField(fields, 'createdAt', _todayIso()),
      );

      if (!invite.isValid) {
        throw Exception('Ovaj pristupni kod je već iskorišten do maksimuma.');
      }

      await _dio.patch(
        '/invites/$cleanCode?updateMask.fieldPaths=usedCount',
        data: {
          'fields': {
            'usedCount': {'integerValue': (invite.usedCount + 1).toString()},
          },
        },
      );
      return invite;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception('Pristupni kod "$cleanCode" nije pronađen ili je neispravan.');
      }
      rethrow;
    }
  }

  Future<AppUser?> refreshUserProfile(String uid) async {
    try {
      final res = await _dio.get('/users/$uid');
      return _userFromFirestoreDoc(res.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<AppUser> incrementUserUsage(AppUser user) async {
    final today = _todayIso();
    final newUsed = (user.lastUsageDate == today ? user.usedToday : 0) + 1;
    final updated = user.copyWith(
      usedToday: newUsed,
      lastUsageDate: today,
    );

    try {
      await _dio.patch(
        '/users/${user.uid}?updateMask.fieldPaths=usedToday&updateMask.fieldPaths=lastUsageDate',
        data: {
          'fields': {
            'usedToday': {'integerValue': newUsed.toString()},
            'lastUsageDate': {'stringValue': today},
          },
        },
      );
    } catch (_) {}
    return updated;
  }

  Future<List<AppUser>> listAllUsers() async {
    final res = await _dio.get('/users', queryParameters: {'pageSize': 200});
    final data = res.data as Map<String, dynamic>;
    final docs = (data['documents'] as List<dynamic>?) ?? [];
    final users = docs
        .map((d) => _userFromFirestoreDoc(d as Map<String, dynamic>))
        .toList();
    users.sort((a, b) {
      if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
      if (a.approved != b.approved) return a.approved ? 1 : -1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return users;
  }

  Future<AppUser> updateUserAdminFields({
    required AppUser user,
    bool? approved,
    bool? blocked,
    int? dailyQuota,
    String? role,
  }) async {
    final updated = user.copyWith(
      approved: approved,
      blocked: blocked,
      dailyQuota: dailyQuota,
      role: role,
    );

    await _dio.patch(
      '/users/${user.uid}?updateMask.fieldPaths=approved&updateMask.fieldPaths=blocked&updateMask.fieldPaths=dailyQuota&updateMask.fieldPaths=role',
      data: {
        'fields': {
          'approved': {'booleanValue': updated.approved},
          'blocked': {'booleanValue': updated.blocked},
          'dailyQuota': {'integerValue': updated.dailyQuota.toString()},
          'role': {'stringValue': updated.role},
        },
      },
    );
    return updated;
  }

  Future<void> deleteUser(String uid) async {
    await _dio.delete('/users/$uid');
  }

  Future<List<InviteCodeItem>> listInviteCodes() async {
    final res = await _dio.get('/invites', queryParameters: {'pageSize': 100});
    final data = res.data as Map<String, dynamic>;
    final docs = (data['documents'] as List<dynamic>?) ?? [];
    return docs.map((d) {
      final fields = ((d as Map<String, dynamic>)['fields'] as Map<String, dynamic>?) ?? {};
      return InviteCodeItem(
        code: _strField(fields, 'code'),
        note: _strField(fields, 'note'),
        role: _strField(fields, 'role', 'user'),
        dailyQuota: _intField(fields, 'dailyQuota', 30),
        maxUses: _intField(fields, 'maxUses', 1),
        usedCount: _intField(fields, 'usedCount', 0),
        createdAt: _strField(fields, 'createdAt'),
      );
    }).toList();
  }

  Future<InviteCodeItem> createInviteCode({
    required String note,
    String role = 'user',
    int dailyQuota = 30,
    int maxUses = 5,
  }) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final suffix = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    final prefix = role == 'premium' ? 'VSP' : 'VS';
    final code = '$prefix-$suffix';

    final item = InviteCodeItem(
      code: code,
      note: note.trim().isEmpty ? (role == 'premium' ? 'Premium pozivnica' : 'Demo pozivnica') : note.trim(),
      role: role,
      dailyQuota: dailyQuota,
      maxUses: maxUses,
      usedCount: 0,
      createdAt: _todayIso(),
    );

    await _dio.patch(
      '/invites/$code',
      data: {
        'fields': {
          'code': {'stringValue': item.code},
          'note': {'stringValue': item.note},
          'role': {'stringValue': item.role},
          'dailyQuota': {'integerValue': item.dailyQuota.toString()},
          'maxUses': {'integerValue': item.maxUses.toString()},
          'usedCount': {'integerValue': '0'},
          'createdAt': {'stringValue': item.createdAt},
        },
      },
    );
    return item;
  }

  Future<void> deleteInviteCode(String code) async {
    await _dio.delete('/invites/$code');
  }
}
