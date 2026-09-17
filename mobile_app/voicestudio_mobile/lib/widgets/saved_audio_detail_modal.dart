import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:share_plus/share_plus.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../models/saved_audio.dart';
import '../state/app_state.dart';
import 'neon_waveform_widget.dart';

class SavedAudioDetailModal extends StatefulWidget {
  final SavedAudio item;

  const SavedAudioDetailModal({super.key, required this.item});

  static void show(BuildContext context, SavedAudio item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavedAudioDetailModal(item: item),
    );
  }

  @override
  State<SavedAudioDetailModal> createState() => _SavedAudioDetailModalState();
}

class _SavedAudioDetailModalState extends State<SavedAudioDetailModal> {
  double _currentSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    final audio = context.read<AppState>().audio;
    _currentSpeed = audio.player.speed;
  }

  Future<void> _shareAudio(File file) async {
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '${widget.item.title} (Voice: ${widget.item.profileName})',
        ),
      );
    }
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: widget.item.text));
    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tekst kopiran u međuspremnik.'),
          backgroundColor: AppTheme.accentCyan,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final audio = state.audio;
    final file = File(widget.item.filePath);
    final fileExists = file.existsSync();

    final text = widget.item.text;
    final wordCount = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final charCount = text.length;

    // Check if this audio is currently playing in the global AudioService
    final isThisItemActive = audio.currentSource != null &&
        (audio.currentSource == file.path || audio.currentSource == widget.item.filePath);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF2E3A52), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accentCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.item.profileName,
                              style: const TextStyle(
                                color: AppTheme.accentCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (widget.item.duration > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${widget.item.duration.toStringAsFixed(1)}s',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Copy Text
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20, color: AppTheme.textSecondary),
                  tooltip: 'Kopiraj tekst',
                  visualDensity: VisualDensity.compact,
                  onPressed: _copyText,
                ),
                // Favorite
                IconButton(
                  icon: Icon(
                    widget.item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: widget.item.isFavorite ? Colors.amber : AppTheme.textSecondary,
                    size: 22,
                  ),
                  tooltip: 'Favorite',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => state.toggleFavoriteAudio(widget.item.id),
                ),
                // Share
                if (fileExists)
                  IconButton(
                    icon: const Icon(Icons.share_rounded, size: 20, color: AppTheme.textSecondary),
                    tooltip: 'Dijeli audio',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _shareAudio(file),
                  ),
                // Close
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.textMuted),
                  tooltip: 'Zatvori',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),

          // Scrollable Full Text Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'KOMPLETAN TEKST',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        '$wordCount riječi • $charCount znakova',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          widget.item.text,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14.5,
                            height: 1.5,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Embedded Media Player
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              16 + MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: const Border(top: BorderSide(color: AppTheme.border)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: fileExists
                ? StreamBuilder<PlayerState>(
                    stream: audio.playerStateStream,
                    builder: (context, stateSnap) {
                      final playerState = stateSnap.data;
                      final isPlaying = isThisItemActive && (playerState?.playing ?? false);

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Waveform
                          NeonWaveformWidget(isPlaying: isPlaying),
                          const SizedBox(height: 6),

                          // Progress Bar
                          StreamBuilder<Duration>(
                            stream: audio.positionStream,
                            builder: (context, posSnap) {
                              final pos = isThisItemActive ? (posSnap.data ?? Duration.zero) : Duration.zero;
                              return StreamBuilder<Duration?>(
                                stream: audio.durationStream,
                                builder: (context, durSnap) {
                                  final dur = isThisItemActive && durSnap.data != null
                                      ? durSnap.data!
                                      : Duration(milliseconds: (widget.item.duration * 1000).round());

                                  return ProgressBar(
                                    progress: pos,
                                    total: dur,
                                    progressBarColor: AppTheme.primary,
                                    baseBarColor: AppTheme.surfaceHighlight,
                                    bufferedBarColor: AppTheme.border,
                                    thumbColor: AppTheme.primaryNeon,
                                    thumbGlowColor: AppTheme.primaryNeon.withValues(alpha: 0.3),
                                    thumbRadius: 6,
                                    barHeight: 4,
                                    timeLabelTextStyle: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 11,
                                    ),
                                    onSeek: (newPos) async {
                                      if (!isThisItemActive) {
                                        await audio.playFile(file);
                                      }
                                      audio.seek(newPos);
                                    },
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 8),

                          // Controls Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Speed selector
                              Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<double>(
                                    value: _currentSpeed,
                                    dropdownColor: AppTheme.surface,
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
                                      if (val != null) {
                                        setState(() => _currentSpeed = val);
                                        audio.setPlaybackSpeed(val);
                                      }
                                    },
                                  ),
                                ),
                              ),

                              // Playback buttons
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.replay_10_rounded, size: 24, color: AppTheme.textSecondary),
                                    tooltip: 'Back 10s',
                                    onPressed: () {
                                      if (isThisItemActive) {
                                        audio.seekRelative(const Duration(seconds: -10));
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  // Play / Pause Circle
                                  GestureDetector(
                                    onTap: () async {
                                      HapticFeedback.lightImpact();
                                      if (isPlaying) {
                                        await audio.pause();
                                      } else {
                                        await audio.playFile(file);
                                      }
                                    },
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [AppTheme.primaryNeon, AppTheme.primary],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primaryNeon.withValues(alpha: 0.35),
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.forward_10_rounded, size: 24, color: AppTheme.textSecondary),
                                    tooltip: 'Forward 10s',
                                    onPressed: () {
                                      if (isThisItemActive) {
                                        audio.seekRelative(const Duration(seconds: 10));
                                      }
                                    },
                                  ),
                                ],
                              ),

                              // Spacer to balance speed selector width
                              const SizedBox(width: 48),
                            ],
                          ),
                        ],
                      );
                    },
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Audio datoteka više ne postoji na uređaju.',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
