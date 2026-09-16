import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:share_plus/share_plus.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../services/audio_service.dart';
import 'neon_waveform_widget.dart';

class NeonAudioPlayer extends StatelessWidget {
  final AudioService audioService;
  final File? currentAudioFile;
  final String title;
  final double currentSpeed;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback? onSaveToLibrary;
  final bool isSaved;

  const NeonAudioPlayer({
    super.key,
    required this.audioService,
    required this.currentAudioFile,
    required this.title,
    required this.currentSpeed,
    required this.onSpeedChanged,
    this.onSaveToLibrary,
    this.isSaved = false,
  });

  Future<void> _shareAudio() async {
    if (currentAudioFile != null && await currentAudioFile!.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(currentAudioFile!.path)],
          text: 'VoiceStudio audio: $title',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentAudioFile == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF3B4866),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Audio Title & Share Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.graphic_eq_rounded, size: 16, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onSaveToLibrary != null)
                    IconButton(
                      icon: Icon(
                        isSaved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                        size: 20,
                        color: isSaved ? AppTheme.accentGreen : AppTheme.textSecondary,
                      ),
                      tooltip: isSaved ? 'Saved to Library' : 'Save to Offline Library',
                      visualDensity: VisualDensity.compact,
                      onPressed: onSaveToLibrary,
                    ),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, size: 18, color: AppTheme.textSecondary),
                    tooltip: 'Share Audio',
                    visualDensity: VisualDensity.compact,
                    onPressed: _shareAudio,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Neon Waveform matching mockup_ui.jpg
          StreamBuilder<PlayerState>(
            stream: audioService.playerStateStream,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data?.playing ?? false;
              return NeonWaveformWidget(isPlaying: isPlaying);
            },
          ),
          const SizedBox(height: 6),

          // Progress Bar
          StreamBuilder<Duration>(
            stream: audioService.positionStream,
            builder: (context, posSnap) {
              final position = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: audioService.durationStream,
                builder: (context, durSnap) {
                  final total = durSnap.data ?? Duration.zero;
                  return ProgressBar(
                    progress: position,
                    total: total,
                    progressBarColor: AppTheme.primary,
                    baseBarColor: AppTheme.surfaceHighlight,
                    bufferedBarColor: AppTheme.border,
                    thumbColor: AppTheme.primaryNeon,
                    thumbGlowColor: AppTheme.primaryNeon.withValues(alpha: 0.3),
                    thumbRadius: 7,
                    barHeight: 5,
                    timeLabelTextStyle: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    onSeek: (duration) {
                      audioService.seek(duration);
                    },
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),

          // Controls Row (Play, Pause, -10s, +10s, Speed)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Speed selector dropdown or chips
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    value: currentSpeed,
                    dropdownColor: AppTheme.surfaceElevated,
                    icon: const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textMuted),
                    style: const TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    items: AppConstants.availableSpeeds.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text('${s}x'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) onSpeedChanged(val);
                    },
                  ),
                ),
              ),

              // Playback Controls
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10_rounded, size: 24, color: AppTheme.textSecondary),
                    tooltip: 'Back 10s',
                    onPressed: () => audioService.seekRelative(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 4),
                  StreamBuilder<PlayerState>(
                    stream: audioService.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final isPlaying = playerState?.playing ?? false;
                      final isCompleted = playerState?.processingState == ProcessingState.completed;

                      return GestureDetector(
                        onTap: () {
                          if (isCompleted) {
                            audioService.seek(Duration.zero);
                            audioService.resume();
                          } else if (isPlaying) {
                            audioService.pause();
                          } else {
                            audioService.resume();
                          }
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF80F7FF), Color(0xFF00E5FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 30,
                            color: const Color(0xFF0A0D14), // Dark icon on bright cyan
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.forward_10_rounded, size: 24, color: AppTheme.textSecondary),
                    tooltip: 'Forward 10s',
                    onPressed: () => audioService.seekRelative(const Duration(seconds: 10)),
                  ),
                ],
              ),

              // Quick Replay
              IconButton(
                icon: const Icon(Icons.restart_alt_rounded, size: 20, color: AppTheme.textMuted),
                tooltip: 'Replay from start',
                onPressed: () {
                  audioService.seek(Duration.zero);
                  audioService.resume();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
