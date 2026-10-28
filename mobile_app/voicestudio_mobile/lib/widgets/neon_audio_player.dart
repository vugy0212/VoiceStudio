import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          // Audio Title + Clearly Labeled "Snimi" Button + Share Icon
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    size: 16, color: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (onSaveToLibrary != null)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSaveToLibrary!();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSaved
                          ? AppTheme.accentGreen.withValues(alpha: 0.2)
                          : AppTheme.accentCyan.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSaved
                            ? AppTheme.accentGreen
                            : AppTheme.accentCyan.withValues(alpha: 0.7),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSaved
                              ? Icons.check_circle_rounded
                              : Icons.save_alt_rounded,
                          size: 15,
                          color: isSaved
                              ? AppTheme.accentGreen
                              : AppTheme.accentCyan,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isSaved ? 'Snimljeno' : 'Snimi',
                          style: TextStyle(
                            color: isSaved
                                ? AppTheme.accentGreen
                                : AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.share_rounded,
                    size: 20, color: AppTheme.accentCyan),
                tooltip: 'Podijeli audio',
                visualDensity: VisualDensity.compact,
                onPressed: _shareAudio,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Neon Waveform
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
                    thumbGlowColor:
                        AppTheme.primaryNeon.withValues(alpha: 0.3),
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

          // Controls Row (Speed, -10s, Play/Pause, STOP, +10s, Replay)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Speed selector dropdown
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
                    icon: const Icon(Icons.arrow_drop_down,
                        size: 16, color: AppTheme.textMuted),
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

              // Playback Controls (Rewind, Play/Pause, STOP, Forward)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10_rounded,
                        size: 23, color: AppTheme.textSecondary),
                    tooltip: '-10s',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        audioService.seekRelative(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 4),
                  StreamBuilder<PlayerState>(
                    stream: audioService.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final isPlaying = playerState?.playing ?? false;
                      final isCompleted = playerState?.processingState ==
                          ProcessingState.completed;

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
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
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF80F7FF),
                                    Color(0xFF00E5FF)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.45),
                                    blurRadius: 16,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isPlaying && !isCompleted
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 29,
                                color: const Color(0xFF0A0D14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // STOP Button
                          GestureDetector(
                            onTap: () async {
                              HapticFeedback.mediumImpact();
                              await audioService.stop();
                              await audioService.seek(Duration.zero);
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isPlaying
                                    ? Colors.redAccent.withValues(alpha: 0.2)
                                    : AppTheme.surfaceElevated,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isPlaying
                                      ? Colors.redAccent
                                      : AppTheme.border,
                                  width: 1.2,
                                ),
                              ),
                              child: Icon(
                                Icons.stop_rounded,
                                size: 22,
                                color: isPlaying
                                    ? Colors.redAccent
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.forward_10_rounded,
                        size: 23, color: AppTheme.textSecondary),
                    tooltip: '+10s',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        audioService.seekRelative(const Duration(seconds: 10)),
                  ),
                ],
              ),

              // Quick Replay
              IconButton(
                icon: const Icon(Icons.restart_alt_rounded,
                    size: 20, color: AppTheme.textMuted),
                tooltip: 'Ponovi od početka',
                visualDensity: VisualDensity.compact,
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
