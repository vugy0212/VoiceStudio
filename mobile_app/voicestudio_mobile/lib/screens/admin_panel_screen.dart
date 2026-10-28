import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/theme.dart';
import '../models/app_user.dart';
import '../models/voice_profile.dart';
import '../state/app_state.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<AppUser> _users = [];
  List<InviteCodeItem> _invites = [];
  HubConnectionConfig? _hubConfig;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final hub = context.read<AppState>().hub;
      final results = await Future.wait([
        hub.listAllUsers(),
        hub.listInviteCodes(),
        hub.fetchConnectionConfig(),
      ]);
      if (mounted) {
        setState(() {
          _users = results[0] as List<AppUser>;
          _invites = results[1] as List<InviteCodeItem>;
          _hubConfig = results[2] as HubConnectionConfig;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleAutoApprove(bool val) async {
    if (_hubConfig == null) return;
    final hub = context.read<AppState>().hub;
    final updated = HubConnectionConfig(
      remoteUrl: _hubConfig!.remoteUrl,
      localUrl: _hubConfig!.localUrl,
      cfClientId: _hubConfig!.cfClientId,
      cfClientSecret: _hubConfig!.cfClientSecret,
      autoApproveNewUsers: val,
      defaultDailyQuota: _hubConfig!.defaultDailyQuota,
      adminEmail: _hubConfig!.adminEmail,
      allowedVoiceIds: _hubConfig!.allowedVoiceIds,
    );
    await hub.saveConnectionConfig(updated);
    if (mounted) setState(() => _hubConfig = updated);
  }

  Future<void> _toggleAllowedVoice(String voiceId, bool allowed) async {
    if (_hubConfig == null) return;
    final hub = context.read<AppState>().hub;
    final currentSet = Set<String>.from(_hubConfig!.allowedVoiceIds);
    if (allowed) {
      currentSet.add(voiceId);
    } else {
      currentSet.remove(voiceId);
    }
    final updated = HubConnectionConfig(
      remoteUrl: _hubConfig!.remoteUrl,
      localUrl: _hubConfig!.localUrl,
      cfClientId: _hubConfig!.cfClientId,
      cfClientSecret: _hubConfig!.cfClientSecret,
      autoApproveNewUsers: _hubConfig!.autoApproveNewUsers,
      defaultDailyQuota: _hubConfig!.defaultDailyQuota,
      adminEmail: _hubConfig!.adminEmail,
      allowedVoiceIds: currentSet.toList(),
    );
    await hub.saveConnectionConfig(updated);
    if (mounted) setState(() => _hubConfig = updated);
  }

  Future<void> _updateUser(
    AppUser user, {
    bool? approved,
    bool? blocked,
    int? dailyQuota,
    String? role,
  }) async {
    final hub = context.read<AppState>().hub;
    HapticFeedback.selectionClick();
    await hub.updateUserAdminFields(
      user: user,
      approved: approved,
      blocked: blocked,
      dailyQuota: dailyQuota,
      role: role,
    );
    await _loadData();
  }

  Future<void> _showCreateInviteDialog() async {
    final noteCtrl = TextEditingController(text: 'Prijatelji / Tim');
    String selectedRole = 'user'; // 'user' (Demo) | 'premium' (Premium)
    int quota = 30;
    int maxUses = 10;

    final created = await showDialog<InviteCodeItem>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceElevated,
              title: const Text('Nova pozivnica (Pristupni kod)', style: TextStyle(fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: noteCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
                      decoration: const InputDecoration(
                        labelText: 'Oznaka / Opis grupe',
                        hintText: 'npr. VIP Tim ili Demo grupa',
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Razina pristupa za ovu pozivnicu:',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Demo (4 glasa)', style: TextStyle(fontSize: 11.5)),
                            selected: selectedRole == 'user',
                            onSelected: (_) => setModalState(() {
                              selectedRole = 'user';
                              quota = 30;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('⭐ Premium (Svi glasovi)', style: TextStyle(fontSize: 11.5)),
                            selected: selectedRole == 'premium',
                            selectedColor: Colors.amber.withValues(alpha: 0.25),
                            onSelected: (_) => setModalState(() {
                              selectedRole = 'premium';
                              quota = 100;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Dnevna kvota po korisniku:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [15, 30, 50, 100, 300].map((q) {
                        return ChoiceChip(
                          label: Text('$q/dan', style: const TextStyle(fontSize: 11.5)),
                          selected: quota == q,
                          onSelected: (_) => setModalState(() => quota = q),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('Maksimalan broj korisnika za ovaj kod:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [1, 5, 10, 25, 100].map((m) {
                        return ChoiceChip(
                          label: Text('$m kor.', style: const TextStyle(fontSize: 11.5)),
                          selected: maxUses == m,
                          onSelected: (_) => setModalState(() => maxUses = m),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Odustani'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final hub = context.read<AppState>().hub;
                    final item = await hub.createInviteCode(
                      note: noteCtrl.text,
                      role: selectedRole,
                      dailyQuota: quota,
                      maxUses: maxUses,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop(item);
                  },
                  child: const Text('Generiraj kod'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _users.where((u) => !u.approved && !u.blocked).length;
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel (Firebase Hub)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan),
            tooltip: 'Osvježi listu',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentCyan,
          labelColor: AppTheme.accentCyan,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: [
            Tab(
              text: pendingCount > 0
                  ? 'Korisnici (${_users.length} • $pendingCount čeka)'
                  : 'Korisnici (${_users.length})',
            ),
            Tab(text: 'Pozivnice (${_invites.length})'),
            const Tab(text: 'Demo Glasovi'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateInviteDialog,
        backgroundColor: AppTheme.primaryNeon,
        foregroundColor: const Color(0xFF0A0D14),
        icon: const Icon(Icons.vpn_key_rounded),
        label: const Text('Novi Pristupni Kod', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Greška: $_error', style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildUsersTab(),
                    _buildInvitesTab(),
                    _buildAllowedVoicesTab(state.profiles),
                  ],
                ),
    );
  }

  Widget _buildUsersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        if (_hubConfig != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: AppTheme.accentCyan, size: 22),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Automatski odobri nove Demo registracije',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Novi korisnici dobivaju Demo pristup (4 glasa), a ovdje ih možete promovirati u Premium ⭐.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _hubConfig!.autoApproveNewUsers,
                  activeThumbColor: AppTheme.accentCyan,
                  onChanged: _toggleAutoApprove,
                ),
              ],
            ),
          ),
        if (_users.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Još nema registriranih korisnika.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ..._users.map(_buildUserCard),
      ],
    );
  }

  Widget _buildUserCard(AppUser user) {
    final bool isPremiumUser = user.role == 'premium';
    final statusColor = user.blocked
        ? Colors.redAccent
        : (!user.approved
            ? Colors.amberAccent
            : (user.isAdmin
                ? AppTheme.primaryNeon
                : (isPremiumUser ? Colors.amber : AppTheme.accentGreen)));

    final statusLabel = user.blocked
        ? 'BLOKIRAN'
        : (user.isAdmin
            ? 'ADMIN'
            : (!user.approved
                ? 'ČEKA ODOBRENJE'
                : (isPremiumUser ? '⭐ PREMIUM (SVI GLASOVI)' : 'DEMO (4 GLASA)')));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: statusColor.withValues(alpha: 0.15),
                child: Icon(
                  user.isAdmin
                      ? Icons.shield_rounded
                      : (isPremiumUser ? Icons.workspace_premium_rounded : Icons.person_rounded),
                  color: statusColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      user.email,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                user.isAdmin
                    ? 'Danas: ${user.effectiveUsedToday} (Svi modeli)'
                    : 'Danas: ${user.effectiveUsedToday} / ${user.dailyQuota} sinteza',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              if (!user.isAdmin)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!user.approved || user.blocked)
                      TextButton.icon(
                        onPressed: () => _updateUser(user, approved: true, blocked: false),
                        icon: const Icon(Icons.check_circle_outline, size: 15, color: AppTheme.accentGreen),
                        label: const Text('Odobri', style: TextStyle(color: AppTheme.accentGreen, fontSize: 11.5)),
                      ),
                    // 1-Tap Toggle between Standard (Demo) and Premium (All Admin Voices)
                    OutlinedButton.icon(
                      onPressed: () => _updateUser(
                        user,
                        approved: true,
                        blocked: false,
                        role: isPremiumUser ? 'user' : 'premium',
                        dailyQuota: isPremiumUser ? 30 : 100,
                      ),
                      icon: Icon(
                        isPremiumUser ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 15,
                        color: Colors.amber,
                      ),
                      label: Text(
                        isPremiumUser ? 'Vrati na Demo' : 'Daj Premium ⭐',
                        style: const TextStyle(color: Colors.amber, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.amber.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    if (!user.blocked)
                      IconButton(
                        tooltip: 'Blokiraj korisnika',
                        onPressed: () => _updateUser(user, blocked: true),
                        icon: const Icon(Icons.block_rounded, size: 17, color: Colors.redAccent),
                        visualDensity: VisualDensity.compact,
                      ),
                    PopupMenuButton<int>(
                      tooltip: 'Promijeni dnevni limit',
                      icon: const Icon(Icons.tune_rounded, size: 18, color: AppTheme.accentCyan),
                      onSelected: (newQuota) => _updateUser(user, dailyQuota: newQuota),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 15, child: Text('Limit: 15 sinteza / dan')),
                        PopupMenuItem(value: 30, child: Text('Limit: 30 sinteza / dan')),
                        PopupMenuItem(value: 50, child: Text('Limit: 50 sinteza / dan')),
                        PopupMenuItem(value: 100, child: Text('Limit: 100 sinteza / dan')),
                        PopupMenuItem(value: 500, child: Text('Limit: 500 sinteza / dan')),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvitesTab() {
    if (_invites.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nema kreiranih pozivnica.\nKliknite "Novi Pristupni Kod" za kreiranje Demo ili Premium ⭐ koda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      itemCount: _invites.length,
      itemBuilder: (ctx, i) {
        final inv = _invites[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: inv.isPremiumInvite
                  ? Colors.amber.withValues(alpha: 0.45)
                  : (inv.isValid ? AppTheme.accentCyan.withValues(alpha: 0.4) : AppTheme.border),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SelectableText(
                          inv.code,
                          style: TextStyle(
                            color: inv.isPremiumInvite ? Colors.amber : AppTheme.accentCyan,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (inv.isPremiumInvite ? Colors.amber : AppTheme.accentCyan)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            inv.isPremiumInvite ? '⭐ PREMIUM' : 'DEMO (4 GLASA)',
                            style: TextStyle(
                              color: inv.isPremiumInvite ? Colors.amber : AppTheme.accentCyan,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${inv.note} • Iskorišteno: ${inv.usedCount}/${inv.maxUses} • Kvota: ${inv.dailyQuota}/dan',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 19, color: AppTheme.textSecondary),
                tooltip: 'Kopiraj kod',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inv.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Kopiran kod: ${inv.code}')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 19, color: AppTheme.accentCyan),
                tooltip: 'Podijeli pozivnicu',
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Pozivnica za VoiceStudio Mobile (${inv.isPremiumInvite ? "Premium pristup svim glasovima" : "Demo verzija"})!\nPristupni kod: ${inv.code}\n(Unesite u tabu "Pozivnica" pri ulasku u aplikaciju)',
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Colors.redAccent),
                tooltip: 'Obriši kod',
                onPressed: () async {
                  await context.read<AppState>().hub.deleteInviteCode(inv.code);
                  await _loadData();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAllowedVoicesTab(List<VoiceProfile> allProfiles) {
    final allowedIds = _hubConfig?.allowedVoiceIds ?? HubConnectionConfig.defaultAllowedVoiceIds;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.35)),
          ),
          child: const Text(
            '• Administrator i ⭐ Premium korisnici vide SVE glasovne modele.\n• Ovdje označite koje glasovne modele vide obični (Demo) korisnici (zadano: Pantić, Šojić, dijete, Bata S.).',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
          ),
        ),
        ...allProfiles.map((p) {
          final isAllowed = allowedIds.contains(p.id);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAllowed
                    ? AppTheme.accentGreen.withValues(alpha: 0.45)
                    : AppTheme.border,
              ),
            ),
            child: SwitchListTile(
              value: isAllowed,
              activeThumbColor: AppTheme.accentGreen,
              title: Text(
                p.name,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                isAllowed
                    ? 'Dostupan u Demo i Premium verziji (ID: ${p.id})'
                    : 'Dostupan samo za ⭐ Premium i Admina (ID: ${p.id})',
                style: TextStyle(
                  color: isAllowed ? AppTheme.accentGreen : Colors.amber,
                  fontSize: 11.5,
                ),
              ),
              onChanged: (val) => _toggleAllowedVoice(p.id, val),
            ),
          );
        }),
      ],
    );
  }
}
