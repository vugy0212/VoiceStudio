import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/voice_profile.dart';
import '../screens/voice_clone_screen.dart';
import '../state/app_state.dart';

class ManageVoicesModal extends StatefulWidget {
  final String? initialSelectedId;

  const ManageVoicesModal({super.key, this.initialSelectedId});

  static void show(BuildContext context, {String? initialSelectedId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManageVoicesModal(initialSelectedId: initialSelectedId),
    );
  }

  @override
  State<ManageVoicesModal> createState() => _ManageVoicesModalState();
}

class _ManageVoicesModalState extends State<ManageVoicesModal> {
  String? _previewingProfileId;

  Future<void> _playProfileSample(VoiceProfile profile) async {
    final state = context.read<AppState>();
    final audioUrl = state.api.getProfileAudioUrl(profile.id);
    final headers = state.api.getAuthHeaders();

    if (_previewingProfileId == profile.id) {
      await state.audio.stop();
      setState(() => _previewingProfileId = null);
      return;
    }

    setState(() => _previewingProfileId = profile.id);
    try {
      await state.audio.playUrl(audioUrl, headers: headers);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Neuspjelo preslušavanje uzorka: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _previewingProfileId = null);
    }
  }

  Future<void> _confirmDelete(VoiceProfile profile) async {
    final state = context.read<AppState>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Obriši glasovni profil', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
          ],
        ),
        content: Text(
          'Jeste li sigurni da želite trajno obrisati profil "${profile.name}"?\n\nOva radnja se ne može poništiti.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Obriši profil'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await state.deleteProfile(profile.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Glasovni profil "${profile.name}" je uspješno obrisan.'),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Greška pri brisanju profila: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1.5),
          left: BorderSide(color: AppTheme.border, width: 1),
          right: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.record_voice_over_rounded, color: AppTheme.accentCyan, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upravljanje profilima',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Odaberite, preslušajte ili obrišite profile glasova',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),

          // Profiles List
          Flexible(
            child: Consumer<AppState>(
              builder: (context, state, _) {
                final profiles = state.profiles;

                if (profiles.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic_off_rounded, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text(
                          'Nema kreiranih profila glasova',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Klonirajte novi glas snimanjem sa mikrofona ili prijenosom audio datoteke.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  itemCount: profiles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final isSelected = state.selectedProfile?.id == profile.id;
                    final isPreviewing = _previewingProfileId == profile.id;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.surfaceHighlight : AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.border,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Profile Initial Icon
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: (isSelected ? AppTheme.primary : AppTheme.accentCyan).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'V',
                                style: TextStyle(
                                  color: isSelected ? AppTheme.primary : AppTheme.accentCyan,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Name & Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        profile.name,
                                        style: TextStyle(
                                          color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                                          fontSize: 14.5,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelected) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Aktivno',
                                          style: TextStyle(
                                            color: AppTheme.primary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  profile.kind == 'clone' ? 'Klonirani referentni glas' : 'Dizajnirani glas',
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),

                          // Action: Preview Sample
                          IconButton(
                            icon: Icon(
                              isPreviewing ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                              color: isPreviewing ? AppTheme.primaryNeon : AppTheme.accentCyan,
                              size: 24,
                            ),
                            tooltip: 'Poslušaj uzorak',
                            onPressed: () => _playProfileSample(profile),
                          ),

                          // Action: Select (if not already active)
                          if (!isSelected)
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => state.selectProfile(profile),
                              child: const Text('Odaberi', style: TextStyle(fontSize: 12.5)),
                            ),

                          // Action: Delete Profile
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 22,
                              color: Colors.redAccent,
                            ),
                            tooltip: 'Obriši profil',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _confirmDelete(profile),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(height: 1, color: AppTheme.border),

          // Bottom Action: Clone New Voice
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                label: const Text('Kloniraj novi glas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceHighlight,
                  foregroundColor: AppTheme.accentCyan,
                  side: BorderSide(color: AppTheme.accentCyan.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const VoiceCloneScreen()),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
