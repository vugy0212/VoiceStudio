import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../state/app_state.dart';
import '../widgets/connection_badge.dart';
import '../widgets/voice_selector_card.dart';
import '../widgets/text_input_card.dart';
import '../widgets/voice_styling_card.dart';
import '../widgets/neon_audio_player.dart';
import '../widgets/speechify_reader_modal.dart';
import 'voice_clone_screen.dart';
import 'speech_to_speech_screen.dart';
import 'dialogue_studio_screen.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'admin_panel_screen.dart';

class HomeTtsScreen extends StatefulWidget {
  const HomeTtsScreen({super.key});

  @override
  State<HomeTtsScreen> createState() => _HomeTtsScreenState();
}

class _HomeTtsScreenState extends State<HomeTtsScreen> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    final initialDraft = context.read<AppState>().draftText;
    _textController = TextEditingController(text: initialDraft);
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted) return;
    context.read<AppState>().setDraftText(_textController.text);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _generateSpeech() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unesite tekst za sintezu govora.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    final state = context.read<AppState>();
    state.generateSpeech(text);
  }

  Future<void> _toggleGatewayPower(AppState state) async {
    if (!state.isConnected || !state.isAdmin) return;
    HapticFeedback.mediumImpact();
    if (state.isBackendSleeping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Budim VoiceStudio GPU engine na računalu...'),
          backgroundColor: AppTheme.accentCyan,
          duration: Duration(seconds: 2),
        ),
      );
      await state.wakeEngine();
    } else {
      final ok = await state.sleepEngine();
      if (mounted && ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('VoiceStudio prebačen u Standby (0% GPU VRAM).'),
            backgroundColor: AppTheme.accentCyan,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildStudioToolsRow(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildToolChip(
            icon: Icons.record_voice_over_rounded,
            label: 'Speech-to-Speech',
            color: AppTheme.accentCyan,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SpeechToSpeechScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          _buildToolChip(
            icon: Icons.forum_rounded,
            label: 'Višeglasni dijalog',
            color: AppTheme.primaryNeon,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DialogueStudioScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          _buildToolChip(
            icon: Icons.auto_fix_high_rounded,
            label: 'Dizajn glasa',
            color: AppTheme.accentGreen,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceCloneScreen(initialTabIndex: 1)),
              );
            },
          ),
          const SizedBox(width: 8),
          _buildToolChip(
            icon: Icons.theater_comedy_rounded,
            label: 'Arhetipovi',
            color: Colors.amberAccent,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceCloneScreen(initialTabIndex: 2)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;

    if (state.draftText != _textController.text) {
      _textController.value = TextEditingValue(
        text: state.draftText,
        selection: TextSelection.collapsed(offset: state.draftText.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryNeon, AppTheme.accentCyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentCyan.withValues(alpha: 0.3),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const Icon(Icons.waves_rounded, color: Color(0xFF0A0D14), size: 18),
            ),
            const SizedBox(width: 8),
            const Text(
              'VoiceStudio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
          ],
        ),
        actions: [
          if (state.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_rounded, size: 21, color: AppTheme.primaryNeon),
              tooltip: 'Admin Panel',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                );
              },
            ),
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.library_music_rounded, size: 21, color: AppTheme.textSecondary),
                tooltip: 'Spremljena biblioteka',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LibraryScreen()),
                  );
                },
              ),
              if (state.savedAudios.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppTheme.accentCyan,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                    child: Text(
                      '${state.savedAudios.length}',
                      style: const TextStyle(color: Color(0xFF0A0D14), fontSize: 8, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 21, color: AppTheme.textSecondary),
            tooltip: 'Povijest generiranja',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 21, color: AppTheme.textSecondary),
            tooltip: 'Moj profil i postavke',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => state.refreshUserAndSyncConfig(),
          color: AppTheme.primary,
          backgroundColor: AppTheme.surfaceElevated,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
            children: [
              // User Quota / Queue Indicator + Connection Badge
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    if (user != null)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                state.isAdmin
                                    ? Icons.shield_rounded
                                    : (state.isPremium
                                        ? Icons.workspace_premium_rounded
                                        : Icons.bolt_rounded),
                                size: 13,
                                color: state.isAdmin
                                    ? AppTheme.primaryNeon
                                    : (state.isPremium
                                        ? Colors.amberAccent
                                        : AppTheme.accentCyan),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  state.isAdmin
                                      ? 'Admin (${user.displayName})'
                                      : '${state.isPremium ? "⭐ Premium" : "Demo"} • Kvota: ${user.remainingQuota}/${user.dailyQuota}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    ConnectionBadge(
                      isConnected: state.isConnected,
                      isChecking: state.isCheckingConnection,
                      isUsingLocal: state.isUsingLocalUrl,
                      backendStatus: state.backendStatus,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        );
                      },
                      onLongPress: state.isAdmin ? () => _toggleGatewayPower(state) : null,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),

            // 1. Voice Profiles Carousel
            VoiceSelectorCard(
              profiles: state.profiles,
              selectedProfile: state.selectedProfile,
              isLoading: state.isLoadingProfiles,
              onSelect: (profile) => state.selectProfile(profile),
              onAddVoice: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceCloneScreen(initialTabIndex: 0)),
                );
              },
            ),
            const SizedBox(height: 14),

            // 1b. Studio Alati Quick Access Bar
            _buildStudioToolsRow(context),
            const SizedBox(height: 16),

            // 2. Text Input Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextInputCard(
                controller: _textController,
                selectedLanguage: state.language,
                onLanguageChanged: (lang) => state.setLanguage(lang),
                onClear: () {
                  _textController.clear();
                  state.setDraftText('');
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 12),

            // 3. Voice Styling & Advanced Controls Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: VoiceStylingCard(
                currentInstruct: state.instruct,
                onInstructChanged: (instruct) => state.setInstruct(instruct),
                currentSteps: state.steps,
                onStepsChanged: (steps) => state.setSteps(steps),
                currentGuidanceScale: state.guidanceScale,
                onGuidanceScaleChanged: (scale) => state.setGuidanceScale(scale),
              ),
            ),
            const SizedBox(height: 14),

            // Error Banner if generation failed
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.errorMessage!,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                        onPressed: () => state.clearError(),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            if (state.errorMessage != null) const SizedBox(height: 14),

            // 4. Action Row (Speechify Reader button + Synthesize / Cancel CTA)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: state.isGenerating
                        ? null
                        : () {
                            final text = _textController.text.trim();
                            if (text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Unesite tekst ili članak za čitanje po odlomcima.'),
                                  backgroundColor: AppTheme.primary,
                                ),
                              );
                              return;
                            }
                            SpeechifyReaderModal.show(context, text);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyan,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_stories_rounded, size: 20),
                        SizedBox(width: 6),
                        Text('Čitač', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: (state.isGenerating || !state.isConnected)
                            ? null
                            : const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        boxShadow: (state.isGenerating || !state.isConnected)
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ],
                      ),
                      child: ElevatedButton(
                        onPressed: (state.isGenerating || !state.isConnected) ? null : _generateSpeech,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          disabledBackgroundColor: AppTheme.surfaceHighlight,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: state.isGenerating
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      state.streamingChunkCount > 0
                                          ? '⚡ Strujanje (${state.streamingChunkCount}. dio, ${state.generationElapsed.toStringAsFixed(1)}s)'
                                          : (state.backendStatus == 'STARTING'
                                              ? 'Buđenje + Sinteza (${state.generationElapsed.toStringAsFixed(1)}s)'
                                              : 'Generiranje (${state.generationElapsed.toStringAsFixed(1)}s)'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.play_circle_filled_rounded, size: 22),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      state.selectedProfile != null
                                          ? 'Sintetiziraj "${state.selectedProfile!.name}"'
                                          : 'Sintetiziraj glas',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  StreamBuilder(
                    stream: state.audio.playerStateStream,
                    builder: (context, snap) {
                      final isAudioPlaying = snap.data?.playing ?? false;
                      if (!state.isGenerating && !isAudioPlaying) {
                        return const SizedBox.shrink();
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              if (state.isGenerating) {
                                await state.cancelGeneration();
                              } else {
                                await state.audio.stop();
                                await state.audio.seek(Duration.zero);
                              }
                            },
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Colors.redAccent.withValues(alpha: 0.2),
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.all(14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.5)),
                              ),
                            ),
                            tooltip: state.isGenerating
                                ? 'Prekini generiranje'
                                : 'Zaustavi reprodukciju (Stop)',
                            icon: const Icon(Icons.stop_rounded, size: 22),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 5. Neon Audio Player
            if (state.lastGeneration != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NeonAudioPlayer(
                  audioService: state.audio,
                  currentAudioFile: state.lastGeneration!.audioFile,
                  title: state.selectedProfile?.name != null
                      ? 'Glas: ${state.selectedProfile!.name}'
                      : 'Generirani govor',
                  currentSpeed: state.speed,
                  onSpeedChanged: (speed) => state.setSpeed(speed),
                  isSaved: state.savedAudios.any(
                    (a) => a.filePath == state.lastGeneration!.audioFile.path ||
                        (a.text == _textController.text && a.profileName == (state.selectedProfile?.name ?? 'Zadani')),
                  ),
                  onSaveToLibrary: () async {
                    final item = await state.saveToLibrary(
                      file: state.lastGeneration!.audioFile,
                      text: _textController.text,
                      profileName: state.selectedProfile?.name ?? 'Zadani',
                      duration: state.lastGeneration?.duration,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Spremljeno "${item.title}" u offline biblioteku!'),
                          backgroundColor: AppTheme.accentGreen,
                          action: SnackBarAction(
                            label: 'OTVORI',
                            textColor: Colors.white,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const LibraryScreen()),
                              );
                            },
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
