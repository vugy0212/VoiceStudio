import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/voice_profile.dart';
import '../state/app_state.dart';
import 'manage_voices_modal.dart';

class BuiltInArchetypePreset {
  final String id;
  final String hrName;
  final String subtitle;
  final String language;
  final String instruct;
  final Map<String, String> vdStates;
  final String sampleScript;
  final IconData icon;

  const BuiltInArchetypePreset({
    required this.id,
    required this.hrName,
    required this.subtitle,
    required this.language,
    required this.instruct,
    required this.vdStates,
    required this.sampleScript,
    required this.icon,
  });

  /// 4 izvorna HR/SR arhetipa (generirana s hrvatskim/srpskim referentnim uzorkom bez engleskog naglaska)
  /// + 2 engleska studijska arhetipa.
  static const List<BuiltInArchetypePreset> presets = [
    BuiltInArchetypePreset(
      id: 'hr_filmski_narator',
      hrName: 'Filmski Narator',
      subtitle: 'HR/SR • Duboki muški',
      language: 'Croatian',
      instruct: 'male, middle-aged, low pitch',
      vdStates: {
        'Gender': 'male',
        'Age': 'middle-aged',
        'Pitch': 'low pitch',
        'Style': 'Auto',
        'EnglishAccent': 'Auto',
        'ChineseDialect': 'Auto',
      },
      sampleScript:
          'Dobar dan i dobro došli. Danas vam donosimo priču koja je stoljećima čekala da bude ispričana.',
      icon: Icons.movie_filter_rounded,
    ),
    BuiltInArchetypePreset(
      id: 'hr_tv_voditelj',
      hrName: 'TV Voditelj',
      subtitle: 'HR/SR • Vijesti i tekst',
      language: 'Croatian',
      instruct: 'male, middle-aged, moderate pitch',
      vdStates: {
        'Gender': 'male',
        'Age': 'middle-aged',
        'Pitch': 'moderate pitch',
        'Style': 'Auto',
        'EnglishAccent': 'Auto',
        'ChineseDialect': 'Auto',
      },
      sampleScript:
          'Dobro večer, pratite središnji pregled najvažnijih događaja današnjeg dana.',
      icon: Icons.live_tv_rounded,
    ),
    BuiltInArchetypePreset(
      id: 'hr_smirena_naratorica',
      hrName: 'Naratorica',
      subtitle: 'HR/SR • Topli ženski',
      language: 'Croatian',
      instruct: 'female, middle-aged, low pitch',
      vdStates: {
        'Gender': 'female',
        'Age': 'middle-aged',
        'Pitch': 'low pitch',
        'Style': 'Auto',
        'EnglishAccent': 'Auto',
        'ChineseDialect': 'Auto',
      },
      sampleScript:
          'U tišini večeri svaka riječ pronalazi svoj miran i jasan put do slušatelja.',
      icon: Icons.menu_book_rounded,
    ),
    BuiltInArchetypePreset(
      id: 'hr_prirodni_zenski',
      hrName: 'Voditeljica',
      subtitle: 'HR/SR • Prirodni glas',
      language: 'Croatian',
      instruct: 'female, young adult, moderate pitch',
      vdStates: {
        'Gender': 'female',
        'Age': 'young adult',
        'Pitch': 'moderate pitch',
        'Style': 'Auto',
        'EnglishAccent': 'Auto',
        'ChineseDialect': 'Auto',
      },
      sampleScript:
          'Pozdrav svima i dobro došli u novu epizodu! Drago mi je što ste danas s nama.',
      icon: Icons.podcasts_rounded,
    ),
    BuiltInArchetypePreset(
      id: 'feat_01_the_documentarian',
      hrName: 'Documentarian (EN)',
      subtitle: 'Engleski • US Narator',
      language: 'English',
      instruct: 'male, middle-aged, low pitch, american accent',
      vdStates: {
        'Gender': 'male',
        'Age': 'middle-aged',
        'Pitch': 'low pitch',
        'Style': 'Auto',
        'EnglishAccent': 'american accent',
        'ChineseDialect': 'Auto',
      },
      sampleScript:
          'The valley had been quiet for a hundred years, and tonight something stirred beneath the bridge.',
      icon: Icons.public_rounded,
    ),
    BuiltInArchetypePreset(
      id: 'feat_03_the_storyteller',
      hrName: 'Storyteller (EN)',
      subtitle: 'Engleski • UK Pripovjedač',
      language: 'English',
      instruct: 'male, elderly, low pitch, british accent',
      vdStates: {
        'Gender': 'male',
        'Age': 'elderly',
        'Pitch': 'low pitch',
        'Style': 'Auto',
        'EnglishAccent': 'british accent',
        'ChineseDialect': 'Auto',
      },
      sampleScript:
          'Long ago, before the maps were drawn, travellers spoke of a hidden kingdom beyond the hills.',
      icon: Icons.auto_fix_high_rounded,
    ),
  ];
}

class VoiceSelectorCard extends StatefulWidget {
  final List<VoiceProfile> profiles;
  final VoiceProfile? selectedProfile;
  final ValueChanged<VoiceProfile> onSelect;
  final VoidCallback onAddVoice;
  final void Function(VoiceProfile)? onPreviewVoice;
  final VoidCallback? onManageVoices;
  final bool isLoading;

  const VoiceSelectorCard({
    super.key,
    required this.profiles,
    required this.selectedProfile,
    required this.onSelect,
    required this.onAddVoice,
    this.onPreviewVoice,
    this.onManageVoices,
    this.isLoading = false,
  });

  @override
  State<VoiceSelectorCard> createState() => _VoiceSelectorCardState();
}

class _VoiceSelectorCardState extends State<VoiceSelectorCard> {
  String _filterMode = 'all';
  String? _activatingArchetypeId;

  Future<void> _onTapArchetype(
    BuildContext context,
    BuiltInArchetypePreset arch,
  ) async {
    HapticFeedback.selectionClick();
    final state = context.read<AppState>();

    final existing = widget.profiles
        .where((p) => p.name.toLowerCase() == arch.hrName.toLowerCase())
        .firstOrNull;

    if (existing != null) {
      widget.onSelect(existing);
      await state.setInstruct(arch.instruct);
      return;
    }

    if (_activatingArchetypeId != null) return;
    setState(() => _activatingArchetypeId = arch.id);

    try {
      final VoiceProfile created;
      if (arch.id.startsWith('hr_')) {
        // Materialize natively in Croatian/Serbian so reference WAV has native HR/SR phonetics!
        created = await state.createDesignedProfile(
          name: arch.hrName,
          vdStates: arch.vdStates,
          instruct: arch.instruct,
          language: arch.language,
          sampleScript: arch.sampleScript,
        );
      } else {
        created = await state.useArchetype(
          arch.id,
          customName: arch.hrName,
        );
      }
      await state.setInstruct(arch.instruct);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '🎭 Arhetip "${created.name}" (${arch.language == "Croatian" ? "HR/SR" : "EN"}) je aktiviran!'),
            backgroundColor: AppTheme.accentGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Greška pri aktivaciji arhetipa: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activatingArchetypeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.profiles;
    final archetypes = BuiltInArchetypePreset.presets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Glasovni profili & Arhetipovi',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (profiles.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          if (widget.onManageVoices != null) {
                            widget.onManageVoices!();
                          } else {
                            ManageVoicesModal.show(context);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceHighlight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.tune_rounded,
                                  size: 13, color: AppTheme.textSecondary),
                              SizedBox(width: 4),
                              Text(
                                'Upravljaj',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: widget.onAddVoice,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162536),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.accentCyan.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              size: 14, color: AppTheme.accentCyan),
                          SizedBox(width: 4),
                          Text(
                            'Kloniraj novi',
                            style: TextStyle(
                              color: AppTheme.accentCyan,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Quick Category Filter Pills (Svi | Klonirani | 🎭 Arhetipovi (6))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFilterChip(
                mode: 'all',
                label: 'Svi (${profiles.length} + ${archetypes.length})',
                icon: Icons.layers_rounded,
                activeColor: AppTheme.accentCyan,
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                mode: 'cloned',
                label: 'Klonirani (${profiles.length})',
                icon: Icons.mic_rounded,
                activeColor: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                mode: 'archetypes',
                label: '🎭 Arhetipovi (${archetypes.length})',
                icon: Icons.theater_comedy_rounded,
                activeColor: Colors.amber,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 112,
          child: widget.isLoading && profiles.isEmpty && _filterMode == 'cloned'
              ? ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: 3,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, _) => Container(
                    width: 110,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accentCyan),
                      ),
                    ),
                  ),
                )
              : _buildCombinedHorizontalList(context, profiles, archetypes),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String mode,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = _filterMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filterMode = mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.18)
              : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected
                ? activeColor.withValues(alpha: 0.7)
                : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? activeColor : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedHorizontalList(
    BuildContext context,
    List<VoiceProfile> profiles,
    List<BuiltInArchetypePreset> archetypes,
  ) {
    final showCloned = _filterMode == 'all' || _filterMode == 'cloned';
    final showArchetypes = _filterMode == 'all' || _filterMode == 'archetypes';

    final items = <Widget>[];

    if (showCloned) {
      for (final profile in profiles) {
        items.add(_buildProfileCard(context, profile));
      }
    }

    if (showArchetypes) {
      for (final arch in archetypes) {
        items.add(_buildArchetypeCard(context, arch, profiles));
      }
    }

    items.add(
      GestureDetector(
        onTap: widget.onAddVoice,
        child: Container(
          width: 88,
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.mic, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(height: 8),
              const Text(
                'Novi glas',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, idx) => items[idx],
    );
  }

  Widget _buildProfileCard(BuildContext context, VoiceProfile profile) {
    final isSelected = widget.selectedProfile?.id == profile.id;
    final color = isSelected ? AppTheme.primary : AppTheme.accentCyan;

    return GestureDetector(
      onTap: () => widget.onSelect(profile),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        ManageVoicesModal.show(context, initialSelectedId: profile.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surfaceHighlight : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                    blurRadius: 10,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.3),
                        color.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: color.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Center(
                    child: Text(
                      profile.name.isNotEmpty
                          ? profile.name[0].toUpperCase()
                          : 'V',
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              profile.kind == 'design' ? 'Arhetip / Dizajn' : 'Kloniran',
              maxLines: 1,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchetypeCard(
    BuildContext context,
    BuiltInArchetypePreset arch,
    List<VoiceProfile> profiles,
  ) {
    final matchingProfile = profiles
        .where((p) => p.name.toLowerCase() == arch.hrName.toLowerCase())
        .firstOrNull;
    final isSelected = matchingProfile != null &&
        widget.selectedProfile?.id == matchingProfile.id;
    final isActivating = _activatingArchetypeId == arch.id;
    final isHr = arch.language == 'Croatian';

    return GestureDetector(
      onTap: () => _onTapArchetype(context, arch),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 112,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF282112)
              : const Color(0xFF171822),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Colors.amber
                : Colors.amber.withValues(alpha: 0.38),
            width: isSelected ? 1.6 : 1.1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.25),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: (isHr ? AppTheme.accentCyan : Colors.amber)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isHr ? 'HR/SR ARHETIP' : 'EN ARHETIP',
                    style: TextStyle(
                      color: isHr ? AppTheme.accentCyan : Colors.amber,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (matchingProfile != null)
                  const Icon(Icons.check_circle_rounded,
                      size: 12, color: AppTheme.accentGreen),
              ],
            ),
            const SizedBox(height: 5),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isActivating
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.amber,
                        ),
                      )
                    : Icon(arch.icon, color: Colors.amber, size: 17),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              arch.hrName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              arch.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
