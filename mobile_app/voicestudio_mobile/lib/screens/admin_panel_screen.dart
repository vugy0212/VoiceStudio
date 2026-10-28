import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/app_user.dart';
import '../models/voice_profile.dart';
import '../state/app_state.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<AppUser> _users = [];
  List<InviteCodeItem> _invites = [];
  HubConnectionConfig? _hubConfig;
  bool _isLoading = true;
  String? _error;
  String? _previewingProfileId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      final appState = context.read<AppState>();
      final hub = appState.hub;
      final results = await Future.wait([
        hub.listAllUsers(),
        hub.listInviteCodes(),
        hub.fetchConnectionConfig(),
      ]);
      if (appState.profiles.isEmpty) {
        await appState.refreshProfiles();
      }
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

  Future<void> _saveHubConfig(HubConnectionConfig updated) async {
    final appState = context.read<AppState>();
    await appState.hub.saveConnectionConfig(updated);
    await appState.api.syncPublicProfilesToGateway(updated.allowedVoiceIds);
    if (mounted) {
      setState(() => _hubConfig = updated);
    }
  }

  Future<void> _toggleAutoApprove(bool val) async {
    if (_hubConfig == null) return;
    await _saveHubConfig(_hubConfig!.copyWith(autoApproveNewUsers: val));
  }

  Future<void> _updateUser(
    AppUser user, {
    bool? approved,
    bool? blocked,
    int? dailyQuota,
    String? role,
    String? voiceGroupId,
    List<String>? customVoiceIds,
  }) async {
    final hub = context.read<AppState>().hub;
    HapticFeedback.selectionClick();
    await hub.updateUserAdminFields(
      user: user,
      approved: approved,
      blocked: blocked,
      dailyQuota: dailyQuota,
      role: role,
      voiceGroupId: voiceGroupId,
      customVoiceIds: customVoiceIds,
    );
    await _loadData();
  }

  // ===========================================================================
  // DIALOG 1: ASSIGN SPECIFIC VOICES OR GROUP TO A SINGLE USER
  // ===========================================================================
  Future<void> _showUserVoiceAssignmentDialog(
    AppUser user,
    List<VoiceProfile> allProfiles,
  ) async {
    final groups = _hubConfig?.voiceGroups ?? VoiceGroup.defaultGroups;
    final demoIds =
        _hubConfig?.allowedVoiceIds ?? HubConnectionConfig.defaultAllowedVoiceIds;

    // Mode: 'demo' | 'premium' | 'group:<id>' | 'custom'
    String selectedMode;
    if (user.voiceGroupId == 'custom') {
      selectedMode = 'custom';
    } else if (user.voiceGroupId.isNotEmpty &&
        groups.any((g) => g.id == user.voiceGroupId)) {
      selectedMode = 'group:${user.voiceGroupId}';
    } else if (user.role == 'premium') {
      selectedMode = 'premium';
    } else {
      selectedMode = 'demo';
    }

    final Set<String> pickedVoiceIds = Set<String>.from(
      user.customVoiceIds.isNotEmpty ? user.customVoiceIds : demoIds,
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.record_voice_over_rounded,
                      color: AppTheme.accentCyan, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Glasovi za: ${user.displayName}',
                      style: const TextStyle(fontSize: 15.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Odaberite paket / grupu ili označite pojedinačne glasove:',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: Text('Demo (${demoIds.length} glasa)',
                                style: const TextStyle(fontSize: 11.5)),
                            selected: selectedMode == 'demo',
                            onSelected: (_) => setModalState(() {
                              selectedMode = 'demo';
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('⭐ Premium (Svi glasovi)',
                                style: TextStyle(fontSize: 11.5)),
                            selected: selectedMode == 'premium',
                            selectedColor:
                                Colors.amber.withValues(alpha: 0.25),
                            onSelected: (_) => setModalState(() {
                              selectedMode = 'premium';
                            }),
                          ),
                          ...groups.map((g) {
                            final key = 'group:${g.id}';
                            return ChoiceChip(
                              label: Text(
                                '👥 ${g.name} (${g.voiceIds.length})',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              selected: selectedMode == key,
                              selectedColor: AppTheme.primaryNeon
                                  .withValues(alpha: 0.25),
                              onSelected: (_) => setModalState(() {
                                selectedMode = key;
                                pickedVoiceIds
                                  ..clear()
                                  ..addAll(g.voiceIds);
                              }),
                            );
                          }),
                          ChoiceChip(
                            label: Text(
                              '🎯 Ručni odabir (${pickedVoiceIds.length})',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            selected: selectedMode == 'custom',
                            selectedColor:
                                AppTheme.accentCyan.withValues(alpha: 0.25),
                            onSelected: (_) => setModalState(() {
                              selectedMode = 'custom';
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (selectedMode == 'custom' ||
                          selectedMode.startsWith('group:')) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              selectedMode == 'custom'
                                  ? 'Pojedinačni odabir glasova (${pickedVoiceIds.length}/${allProfiles.length}):'
                                  : 'Glasovi u odabranoj grupi (kliknite glas za prilagodbu):',
                              style: const TextStyle(
                                color: AppTheme.accentCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Row(
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => setModalState(() {
                                    selectedMode = 'custom';
                                    pickedVoiceIds.addAll(
                                        allProfiles.map((e) => e.id));
                                  }),
                                  child: const Text('Svi',
                                      style: TextStyle(fontSize: 11.5)),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => setModalState(() {
                                    selectedMode = 'custom';
                                    pickedVoiceIds.clear();
                                  }),
                                  child: const Text('Nijedan',
                                      style: TextStyle(fontSize: 11.5)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 270),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: allProfiles.length,
                            itemBuilder: (_, idx) {
                              final p = allProfiles[idx];
                              final checked = pickedVoiceIds.contains(p.id);
                              return CheckboxListTile(
                                dense: true,
                                value: checked,
                                activeColor: AppTheme.accentCyan,
                                title: Text(
                                  p.name,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'ID: ${p.id} • ${p.language}',
                                  style: const TextStyle(
                                      color: AppTheme.textMuted, fontSize: 10.5),
                                ),
                                onChanged: (val) {
                                  setModalState(() {
                                    // If editing a preset group's checkboxes for this user, switch to custom
                                    selectedMode = 'custom';
                                    if (val == true) {
                                      pickedVoiceIds.add(p.id);
                                    } else {
                                      pickedVoiceIds.remove(p.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Odustani'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('Spremi pristup'),
                  onPressed: () async {
                    if (selectedMode == 'demo') {
                      await _updateUser(
                        user,
                        approved: true,
                        role: 'user',
                        voiceGroupId: '',
                        customVoiceIds: const [],
                      );
                    } else if (selectedMode == 'premium') {
                      await _updateUser(
                        user,
                        approved: true,
                        role: 'premium',
                        voiceGroupId: '',
                        customVoiceIds: const [],
                      );
                    } else if (selectedMode.startsWith('group:')) {
                      final gId = selectedMode.replaceFirst('group:', '');
                      final grp = groups.firstWhere((g) => g.id == gId);
                      await _updateUser(
                        user,
                        approved: true,
                        role: 'user',
                        voiceGroupId: gId,
                        customVoiceIds: grp.voiceIds,
                      );
                    } else {
                      await _updateUser(
                        user,
                        approved: true,
                        role: 'user',
                        voiceGroupId: 'custom',
                        customVoiceIds: pickedVoiceIds.toList(),
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Ažuriran pristup glasovima za korisnika ${user.displayName}!'),
          backgroundColor: AppTheme.accentGreen,
        ),
      );
    }
  }

  // ===========================================================================
  // DIALOG 2: CREATE OR EDIT A VOICE GROUP (GRUPA GLASOVA)
  // ===========================================================================
  Future<void> _showEditVoiceGroupDialog({
    VoiceGroup? existingGroup,
    bool isDefaultDemoGroup = false,
    required List<VoiceProfile> allProfiles,
  }) async {
    if (_hubConfig == null) return;

    final nameCtrl = TextEditingController(
      text: isDefaultDemoGroup
          ? 'Demo Grupa (Zadano za obične korisnike)'
          : (existingGroup?.name ?? ''),
    );
    final Set<String> selectedIds = Set<String>.from(
      isDefaultDemoGroup
          ? _hubConfig!.allowedVoiceIds
          : (existingGroup?.voiceIds ?? _hubConfig!.allowedVoiceIds),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(
                isDefaultDemoGroup
                    ? 'Uredi Demo Grupu Glasova'
                    : (existingGroup == null
                        ? 'Nova Grupa Glasova'
                        : 'Uredi grupu: ${existingGroup.name}'),
                style: const TextStyle(fontSize: 16),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isDefaultDemoGroup) ...[
                        TextField(
                          controller: nameCtrl,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Naziv grupe glasova',
                            hintText: 'npr. Političari, Glumci, VIP Tim...',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Odabrano glasova: ${selectedIds.length} / ${allProfiles.length}',
                            style: const TextStyle(
                              color: AppTheme.accentCyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => setModalState(() {
                                  selectedIds
                                      .addAll(allProfiles.map((e) => e.id));
                                }),
                                child: const Text('Svi',
                                    style: TextStyle(fontSize: 11.5)),
                              ),
                              TextButton(
                                onPressed: () => setModalState(() {
                                  selectedIds.clear();
                                }),
                                child: const Text('Očisti',
                                    style: TextStyle(fontSize: 11.5)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: allProfiles.length,
                          itemBuilder: (_, idx) {
                            final p = allProfiles[idx];
                            final isChecked = selectedIds.contains(p.id);
                            return CheckboxListTile(
                              dense: true,
                              value: isChecked,
                              activeColor: AppTheme.accentGreen,
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'ID: ${p.id} • ${p.language}',
                                style: const TextStyle(
                                    color: AppTheme.textMuted, fontSize: 11),
                              ),
                              onChanged: (val) {
                                setModalState(() {
                                  if (val == true) {
                                    selectedIds.add(p.id);
                                  } else {
                                    selectedIds.remove(p.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Odustani'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 17),
                  label: const Text('Spremi grupu'),
                  onPressed: () async {
                    if (isDefaultDemoGroup) {
                      await _saveHubConfig(
                        _hubConfig!.copyWith(
                          allowedVoiceIds: selectedIds.toList(),
                        ),
                      );
                    } else {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      final groups =
                          List<VoiceGroup>.from(_hubConfig!.voiceGroups);
                      if (existingGroup != null) {
                        final idx = groups
                            .indexWhere((g) => g.id == existingGroup.id);
                        if (idx >= 0) {
                          groups[idx] = existingGroup.copyWith(
                            name: name,
                            voiceIds: selectedIds.toList(),
                          );
                        }
                      } else {
                        final newId =
                            'grp_${DateTime.now().millisecondsSinceEpoch}';
                        groups.add(
                          VoiceGroup(
                            id: newId,
                            name: name,
                            voiceIds: selectedIds.toList(),
                          ),
                        );
                      }
                      await _saveHubConfig(
                        _hubConfig!.copyWith(voiceGroups: groups),
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // DIALOG 3: EDIT VOICE MODEL METADATA (NAME, LANGUAGE, REF_TEXT, INSTRUCT)
  // ===========================================================================
  Future<void> _showEditVoiceProfileDialog(VoiceProfile profile) async {
    final appState = context.read<AppState>();
    final nameCtrl = TextEditingController(text: profile.name);
    final refTextCtrl = TextEditingController(text: profile.refText ?? '');
    final instructCtrl = TextEditingController(text: profile.instruct ?? '');
    String selectedLang =
        AppConstants.availableLanguages.contains(profile.language)
            ? profile.language
            : 'Auto';

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.edit_note_rounded,
                      color: AppTheme.accentCyan, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uredi glas: ${profile.name}',
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: 'Naziv glasovnog modela',
                        hintText: 'npr. Pantić, Šojić, Dida Šime...',
                        prefixIcon: Icon(Icons.badge_outlined,
                            size: 19, color: AppTheme.accentCyan),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Zadani jezik modela:',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedLang,
                          isExpanded: true,
                          dropdownColor: AppTheme.surfaceElevated,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13.5),
                          items: AppConstants.availableLanguages.map((lang) {
                            return DropdownMenuItem(
                                value: lang, child: Text(lang));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedLang = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: refTextCtrl,
                      maxLines: 3,
                      minLines: 2,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Transkript referentne snimke (ref_text)',
                        hintText:
                            'Točan tekst koji je izgovoren na uzorku glasa...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: instructCtrl,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Stilska uputa / oznake (instruct)',
                        hintText: 'npr. male, middle-aged, low pitch',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Odustani'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 17),
                  label: const Text('Spremi izmjene'),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    try {
                      await appState.updateProfile(
                        profileId: profile.id,
                        name: nameCtrl.text.trim(),
                        language: selectedLang,
                        refText: refTextCtrl.text.trim(),
                        instruct: instructCtrl.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Greška: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Glasovni model je uspješno ažuriran!'),
          backgroundColor: AppTheme.accentGreen,
        ),
      );
      setState(() {});
    }
  }

  Future<void> _playVoiceSample(VoiceProfile profile) async {
    final state = context.read<AppState>();
    if (_previewingProfileId == profile.id) {
      await state.audio.stop();
      setState(() => _previewingProfileId = null);
      return;
    }
    setState(() => _previewingProfileId = profile.id);
    try {
      await state.audio.playUrl(
        state.api.getProfileAudioUrl(profile.id),
        headers: state.api.getAuthHeaders(),
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _previewingProfileId = null);
    }
  }

  // ===========================================================================
  // DIALOG 4: CREATE INVITE CODE WITH ROLE OR SPECIFIC GROUP / VOICES
  // ===========================================================================
  Future<void> _showCreateInviteDialog(List<VoiceProfile> allProfiles) async {
    final noteCtrl = TextEditingController(text: 'Prijatelji / Tim');
    final groups = _hubConfig?.voiceGroups ?? VoiceGroup.defaultGroups;
    String selectedOption = 'demo'; // 'demo' | 'premium' | 'group:<id>'
    int quota = 30;
    int maxUses = 10;

    final created = await showDialog<InviteCodeItem>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceElevated,
              title: const Text('Nova pozivnica (Pristupni kod)',
                  style: TextStyle(fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: noteCtrl,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13.5),
                      decoration: const InputDecoration(
                        labelText: 'Oznaka / Opis pozivnice',
                        hintText: 'npr. Ekipa ili VIP korisnici',
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Razina pristupa ili grupa glasova za kod:',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Demo (Zadani glasovi)',
                              style: TextStyle(fontSize: 11.5)),
                          selected: selectedOption == 'demo',
                          onSelected: (_) => setModalState(() {
                            selectedOption = 'demo';
                            quota = 30;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('⭐ Premium (Svi glasovi)',
                              style: TextStyle(fontSize: 11.5)),
                          selected: selectedOption == 'premium',
                          selectedColor: Colors.amber.withValues(alpha: 0.25),
                          onSelected: (_) => setModalState(() {
                            selectedOption = 'premium';
                            quota = 100;
                          }),
                        ),
                        ...groups.map((g) {
                          final key = 'group:${g.id}';
                          return ChoiceChip(
                            label: Text('👥 Grupa: ${g.name} (${g.voiceIds.length})',
                                style: const TextStyle(fontSize: 11.5)),
                            selected: selectedOption == key,
                            selectedColor:
                                AppTheme.primaryNeon.withValues(alpha: 0.25),
                            onSelected: (_) => setModalState(() {
                              selectedOption = key;
                              quota = 50;
                            }),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Dnevna kvota po korisniku:',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [15, 30, 50, 100, 300].map((q) {
                        return ChoiceChip(
                          label: Text('$q/dan',
                              style: const TextStyle(fontSize: 11.5)),
                          selected: quota == q,
                          onSelected: (_) => setModalState(() => quota = q),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('Maksimalan broj korisnika za ovaj kod:',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [1, 5, 10, 25, 100].map((m) {
                        return ChoiceChip(
                          label: Text('$m kor.',
                              style: const TextStyle(fontSize: 11.5)),
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
                    String role = 'user';
                    String groupId = '';
                    List<String> customIds = const [];

                    if (selectedOption == 'premium') {
                      role = 'premium';
                    } else if (selectedOption.startsWith('group:')) {
                      groupId = selectedOption.replaceFirst('group:', '');
                      final grp = groups.firstWhere((g) => g.id == groupId);
                      customIds = grp.voiceIds;
                    }

                    final item = await hub.createInviteCode(
                      note: noteCtrl.text,
                      role: role,
                      voiceGroupId: groupId,
                      customVoiceIds: customIds,
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
        title: const Text('Admin Panel (Upravljanje)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan),
            tooltip: 'Osvježi podatke',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppTheme.accentCyan,
          labelColor: AppTheme.accentCyan,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: [
            Tab(
              text: pendingCount > 0
                  ? 'Korisnici (${_users.length} • $pendingCount čeka)'
                  : 'Korisnici (${_users.length})',
            ),
            const Tab(text: 'Grupe Glasova'),
            Tab(text: 'Uredi Glasove (${state.profiles.length})'),
            Tab(text: 'Pozivnice (${_invites.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateInviteDialog(state.profiles),
        backgroundColor: AppTheme.primaryNeon,
        foregroundColor: const Color(0xFF0A0D14),
        icon: const Icon(Icons.vpn_key_rounded),
        label: const Text('Nova Pozivnica',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentCyan))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Greška: $_error',
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildUsersTab(state.profiles),
                    _buildGroupsTab(state.profiles),
                    _buildEditVoicesTab(state.profiles),
                    _buildInvitesTab(),
                  ],
                ),
    );
  }

  // ===========================================================================
  // TAB 1: USERS & PER-USER VOICE / GROUP SELECTION
  // ===========================================================================
  Widget _buildUsersTab(List<VoiceProfile> allProfiles) {
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
                const Icon(Icons.verified_user_outlined,
                    color: AppTheme.accentCyan, size: 22),
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
                        'Svakom korisniku ispod možete dodijeliti grupu glasova, pojedinačne glasove ili ⭐ Premium.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11.5),
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
        ..._users.map((u) => _buildUserCard(u, allProfiles)),
      ],
    );
  }

  String _describeUserVoiceAccess(AppUser user) {
    if (user.isAdmin) return 'ADMIN (SVI GLASOVI)';
    if (user.blocked) return 'BLOKIRAN';
    if (!user.approved) return 'ČEKA ODOBRENJE';

    final groups = _hubConfig?.voiceGroups ?? VoiceGroup.defaultGroups;
    if (user.voiceGroupId == 'custom') {
      return 'ODABRANO (${user.customVoiceIds.length} GLASOVA)';
    }
    if (user.voiceGroupId.isNotEmpty) {
      final grp = groups.where((g) => g.id == user.voiceGroupId).firstOrNull;
      if (grp != null) {
        return 'GRUPA: ${grp.name.toUpperCase()} (${grp.voiceIds.length})';
      }
    }
    if (user.role == 'premium') return '⭐ PREMIUM (SVI GLASOVI)';
    final demoCount = _hubConfig?.allowedVoiceIds.length ?? 4;
    return 'DEMO ($demoCount GLASA)';
  }

  Widget _buildUserCard(AppUser user, List<VoiceProfile> allProfiles) {
    final bool isPremiumUser =
        user.role == 'premium' && user.voiceGroupId.isEmpty;
    final statusColor = user.blocked
        ? Colors.redAccent
        : (!user.approved
            ? Colors.amberAccent
            : (user.isAdmin
                ? AppTheme.primaryNeon
                : (isPremiumUser
                    ? Colors.amber
                    : (user.voiceGroupId.isNotEmpty
                        ? AppTheme.accentCyan
                        : AppTheme.accentGreen))));

    final statusLabel = _describeUserVoiceAccess(user);

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
                      : (isPremiumUser
                          ? Icons.workspace_premium_rounded
                          : Icons.person_rounded),
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
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9.5,
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
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                user.isAdmin
                    ? 'Danas: ${user.effectiveUsedToday} (Svi modeli)'
                    : 'Danas: ${user.effectiveUsedToday} / ${user.dailyQuota} sinteza',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
              if (!user.isAdmin)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!user.approved || user.blocked)
                      TextButton.icon(
                        onPressed: () =>
                            _updateUser(user, approved: true, blocked: false),
                        icon: const Icon(Icons.check_circle_outline,
                            size: 15, color: AppTheme.accentGreen),
                        label: const Text('Odobri',
                            style: TextStyle(
                                color: AppTheme.accentGreen, fontSize: 11.5)),
                      ),
                    // Select Specific Voices or Group for this User
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showUserVoiceAssignmentDialog(user, allProfiles),
                      icon: const Icon(Icons.record_voice_over_rounded,
                          size: 14, color: AppTheme.accentCyan),
                      label: const Text(
                        'Glasovi / Grupa',
                        style: TextStyle(
                          color: AppTheme.accentCyan,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color:
                                AppTheme.accentCyan.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    // 1-Tap Toggle Premium
                    OutlinedButton.icon(
                      onPressed: () => _updateUser(
                        user,
                        approved: true,
                        blocked: false,
                        role: isPremiumUser ? 'user' : 'premium',
                        voiceGroupId: '',
                        customVoiceIds: const [],
                        dailyQuota: isPremiumUser ? 30 : 100,
                      ),
                      icon: Icon(
                        isPremiumUser
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 15,
                        color: Colors.amber,
                      ),
                      label: Text(
                        isPremiumUser ? 'Demo' : 'Premium ⭐',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: Colors.amber.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    if (!user.blocked)
                      IconButton(
                        tooltip: 'Blokiraj korisnika',
                        onPressed: () => _updateUser(user, blocked: true),
                        icon: const Icon(Icons.block_rounded,
                            size: 17, color: Colors.redAccent),
                        visualDensity: VisualDensity.compact,
                      ),
                    PopupMenuButton<int>(
                      tooltip: 'Promijeni dnevni limit',
                      icon: const Icon(Icons.tune_rounded,
                          size: 18, color: AppTheme.accentCyan),
                      onSelected: (newQuota) =>
                          _updateUser(user, dailyQuota: newQuota),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 15, child: Text('Limit: 15 sinteza / dan')),
                        PopupMenuItem(
                            value: 30, child: Text('Limit: 30 sinteza / dan')),
                        PopupMenuItem(
                            value: 50, child: Text('Limit: 50 sinteza / dan')),
                        PopupMenuItem(
                            value: 100,
                            child: Text('Limit: 100 sinteza / dan')),
                        PopupMenuItem(
                            value: 500,
                            child: Text('Limit: 500 sinteza / dan')),
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

  // ===========================================================================
  // TAB 2: VOICE GROUPS (DEMO GROUP + CUSTOM GROUPS)
  // ===========================================================================
  Widget _buildGroupsTab(List<VoiceProfile> allProfiles) {
    final demoIds =
        _hubConfig?.allowedVoiceIds ?? HubConnectionConfig.defaultAllowedVoiceIds;
    final groups = _hubConfig?.voiceGroups ?? VoiceGroup.defaultGroups;

    String resolveNames(List<String> ids) {
      final names = allProfiles
          .where((p) => ids.contains(p.id))
          .map((p) => p.name)
          .toList();
      if (names.isEmpty) return '${ids.length} odabranih glasova';
      return names.join(', ');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Kreirajte grupe glasova i dodijelite ih korisnicima ili pozivnicama.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () =>
                  _showEditVoiceGroupDialog(allProfiles: allProfiles),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nova Grupa'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentCyan,
                foregroundColor: const Color(0xFF071018),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 1. Default Demo Group Card
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.accentGreen.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_user_rounded,
                        color: AppTheme.accentGreen, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Zadana Demo Grupa',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${demoIds.length} glasova za obične (Demo) korisnike',
                          style: const TextStyle(
                              color: AppTheme.accentGreen, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showEditVoiceGroupDialog(
                      isDefaultDemoGroup: true,
                      allProfiles: allProfiles,
                    ),
                    icon: const Icon(Icons.checklist_rounded, size: 16),
                    label: const Text('Odaberi glasove',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Uključeni glasovi: ${resolveNames(demoIds)}',
                style:
                    const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),

        // 2. Custom / Named Voice Groups
        ...groups.map((grp) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppTheme.primaryNeon.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNeon.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.workspaces_rounded,
                          color: AppTheme.primaryNeon, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grp.name,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${grp.voiceIds.length} glasova u grupi',
                            style: const TextStyle(
                                color: AppTheme.accentCyan, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded,
                          size: 19, color: AppTheme.accentCyan),
                      tooltip: 'Uredi naziv i glasove u grupi',
                      onPressed: () => _showEditVoiceGroupDialog(
                        existingGroup: grp,
                        allProfiles: allProfiles,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 19, color: Colors.redAccent),
                      tooltip: 'Obriši grupu',
                      onPressed: () async {
                        if (_hubConfig == null) return;
                        final next = _hubConfig!.voiceGroups
                            .where((g) => g.id != grp.id)
                            .toList();
                        await _saveHubConfig(
                            _hubConfig!.copyWith(voiceGroups: next));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Glasovi: ${resolveNames(grp.voiceIds)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: EDIT ALL VOICE MODELS (NAME, LANGUAGE, REF_TEXT, SAMPLE PREVIEW, DELETE)
  // ===========================================================================
  Widget _buildEditVoicesTab(List<VoiceProfile> allProfiles) {
    final appState = context.read<AppState>();
    final demoIds =
        _hubConfig?.allowedVoiceIds ?? HubConnectionConfig.defaultAllowedVoiceIds;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
          ),
          child: const Text(
            'Ovdje možete preimenovati bilo koji glasovni model, promijeniti mu zadani jezik ili transkript, preslušati referentni uzorak ili obrisati model.',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
        ),
        ...allProfiles.map((p) {
          final isDemo = demoIds.contains(p.id);
          final isPlaying = _previewingProfileId == p.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDemo
                    ? AppTheme.accentGreen.withValues(alpha: 0.4)
                    : AppTheme.border,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.15),
                  child: Text(
                    p.name.isNotEmpty ? p.name[0].toUpperCase() : 'V',
                    style: const TextStyle(
                      color: AppTheme.accentCyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (isDemo
                                      ? AppTheme.accentGreen
                                      : Colors.amber)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isDemo ? 'DEMO' : '⭐ PREMIUM',
                              style: TextStyle(
                                color: isDemo
                                    ? AppTheme.accentGreen
                                    : Colors.amber,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${p.id} • Jezik: ${p.language}',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.stop_circle_rounded
                        : Icons.volume_up_rounded,
                    color: isPlaying
                        ? AppTheme.primaryNeon
                        : AppTheme.accentCyan,
                    size: 21,
                  ),
                  tooltip: 'Preslušaj uzorak glasa',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _playVoiceSample(p),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded,
                      color: AppTheme.accentCyan, size: 20),
                  tooltip: 'Uredi naziv i postavke glasa',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showEditVoiceProfileDialog(p),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 20),
                  tooltip: 'Obriši glas',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppTheme.surfaceElevated,
                        title: Text('Obriši glas "${p.name}"?'),
                        content: const Text(
                            'Ova radnja trajno briše glasovni model sa poslužitelja.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Odustani'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Obriši'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await appState.deleteProfile(p.id);
                      if (mounted) setState(() {});
                    }
                  },
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ===========================================================================
  // TAB 4: INVITE CODES
  // ===========================================================================
  Widget _buildInvitesTab() {
    if (_invites.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nema kreiranih pozivnica.\nKliknite "Nova Pozivnica" za kreiranje Demo, Grupa ili Premium ⭐ koda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    final groups = _hubConfig?.voiceGroups ?? VoiceGroup.defaultGroups;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      itemCount: _invites.length,
      itemBuilder: (ctx, i) {
        final inv = _invites[i];
        String badgeText = inv.isPremiumInvite ? '⭐ PREMIUM' : 'DEMO';
        if (inv.voiceGroupId.isNotEmpty) {
          final grp =
              groups.where((g) => g.id == inv.voiceGroupId).firstOrNull;
          badgeText = grp != null
              ? 'GRUPA: ${grp.name.toUpperCase()}'
              : 'PRILAGOĐENO (${inv.customVoiceIds.length})';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: inv.isPremiumInvite
                  ? Colors.amber.withValues(alpha: 0.45)
                  : (inv.isValid
                      ? AppTheme.accentCyan.withValues(alpha: 0.4)
                      : AppTheme.border),
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
                            color: inv.isPremiumInvite
                                ? Colors.amber
                                : AppTheme.accentCyan,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (inv.isPremiumInvite
                                    ? Colors.amber
                                    : AppTheme.accentCyan)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: inv.isPremiumInvite
                                  ? Colors.amber
                                  : AppTheme.accentCyan,
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
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    size: 19, color: AppTheme.textSecondary),
                tooltip: 'Kopiraj kod',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inv.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Kopiran kod: ${inv.code}')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded,
                    size: 19, color: AppTheme.accentCyan),
                tooltip: 'Podijeli pozivnicu',
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Pozivnica za VoiceStudio Mobile ($badgeText)!\nPristupni kod: ${inv.code}\n(Unesite u tabu "Pozivnica" pri ulasku u aplikaciju)',
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 19, color: Colors.redAccent),
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
}
