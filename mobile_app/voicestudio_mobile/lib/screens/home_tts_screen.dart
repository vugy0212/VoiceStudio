import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../state/app_state.dart';
import '../widgets/connection_badge.dart';
import '../widgets/voice_selector_card.dart';
import '../widgets/text_input_card.dart';
import '../widgets/neon_audio_player.dart';
import '../widgets/speechify_reader_modal.dart';
import 'voice_clone_screen.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

class HomeTtsScreen extends StatefulWidget {
  const HomeTtsScreen({super.key});

  @override
  State<HomeTtsScreen> createState() => _HomeTtsScreenState();
}

class _HomeTtsScreenState extends State<HomeTtsScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _generateSpeech() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some text to synthesize.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    final state = context.read<AppState>();
    state.generateSpeech(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

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
          // Saved Offline Library Button with Badge
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.library_music_rounded, size: 21, color: AppTheme.textSecondary),
                tooltip: 'Saved Library',
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
          // History Button
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 21, color: AppTheme.textSecondary),
            tooltip: 'Generation History',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          // Settings Button
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 21, color: AppTheme.textSecondary),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => state.testConnectionAndRefresh(),
        color: AppTheme.primary,
        backgroundColor: AppTheme.surfaceElevated,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // Cloudflare Connection Badge (Dedicated placement matching mockup_ui.jpg)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: ConnectionBadge(
                  isConnected: state.isConnected,
                  isChecking: state.isCheckingConnection,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 1. Voice Profiles Carousel
            VoiceSelectorCard(
              profiles: state.profiles,
              selectedProfile: state.selectedProfile,
              onSelect: (profile) => state.selectProfile(profile),
              onAddVoice: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceCloneScreen()),
                );
              },
            ),
            const SizedBox(height: 20),

            // 2. Text Input Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextInputCard(
                controller: _textController,
                selectedLanguage: state.language,
                onLanguageChanged: (lang) => state.setLanguage(lang),
                onClear: () {
                  _textController.clear();
                  setState(() {});
                },
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

            // 4. Action Row (Speechify Reader button + Synthesize CTA)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Speechify Reader Mode Button
                  OutlinedButton(
                    onPressed: () {
                      final text = _textController.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter text or an article to read in Speechify mode.'),
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
                        Text('Reader', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Synthesize CTA Button
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
                                Text(
                                  state.streamingChunkCount > 0
                                      ? '⚡ Strujanje (${state.streamingChunkCount}. dio, ${state.generationElapsed.toStringAsFixed(1)}s)...'
                                      : 'Generiranje (${state.generationElapsed.toStringAsFixed(1)}s)...',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
                                        ? 'Sintetiziraj glas "${state.selectedProfile!.name}"'
                                        : 'Sintetiziraj Glas',
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
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 5. Neon Audio Player (Shows generated speech)
            if (state.lastGeneration != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NeonAudioPlayer(
                  audioService: state.audio,
                  currentAudioFile: state.lastGeneration!.audioFile,
                  title: state.selectedProfile?.name != null
                      ? 'Voice: ${state.selectedProfile!.name}'
                      : 'Generated Speech',
                  currentSpeed: state.speed,
                  onSpeedChanged: (speed) => state.setSpeed(speed),
                  isSaved: state.savedAudios.any(
                    (a) => a.filePath == state.lastGeneration!.audioFile.path,
                  ),
                  onSaveToLibrary: () async {
                    final item = await state.saveToLibrary(
                      file: state.lastGeneration!.audioFile,
                      text: _textController.text,
                      profileName: state.selectedProfile?.name ?? 'Default',
                      duration: state.lastGeneration?.duration,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Saved "${item.title}" to offline library!'),
                          backgroundColor: AppTheme.accentGreen,
                          action: SnackBarAction(
                            label: 'VIEW',
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
    );
  }
}
