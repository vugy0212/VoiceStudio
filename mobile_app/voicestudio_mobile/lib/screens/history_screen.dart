import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../config/theme.dart';
import '../state/app_state.dart';
import '../models/generation_history.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _currentlyPlayingId;
  StreamSubscription<PlayerState>? _playerSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playerSub?.cancel();
    final audio = context.read<AppState>().audio;
    _playerSub = audio.playerStateStream.listen((playerState) {
      if (!mounted) return;
      if (!playerState.playing || playerState.processingState == ProcessingState.completed) {
        if (_currentlyPlayingId != null) {
          setState(() => _currentlyPlayingId = null);
        }
      }
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    super.dispose();
  }

  Future<void> _playHistoryItem(GenerationHistory item) async {
    final state = context.read<AppState>();
    if (_currentlyPlayingId == item.id) {
      await state.audio.pause();
      setState(() => _currentlyPlayingId = null);
      return;
    }

    final url = state.api.getAudioFileUrl(item.filename);
    final headers = state.api.getAuthHeaders();

    setState(() => _currentlyPlayingId = item.id);
    try {
      await state.audio.playUrl(url, headers: headers);
    } catch (_) {
      if (mounted) setState(() => _currentlyPlayingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generation History'),
        actions: [
          IconButton(
            icon: state.isLoadingHistory
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                  )
                : const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan),
            onPressed: state.isLoadingHistory ? null : () => state.refreshHistory(),
          ),
        ],
      ),
      body: state.history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.history_rounded, size: 32, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No generations yet',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Generated speech from your PC will appear here.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = state.history[index];
                final isPlaying = _currentlyPlayingId == item.id;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isPlaying ? AppTheme.primary : AppTheme.border,
                      width: isPlaying ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.profileName ?? 'Clone',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (item.duration > 0) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${item.duration.toStringAsFixed(1)}s',
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                                ),
                              ],
                            ],
                          ),
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                              color: AppTheme.primaryNeon,
                              size: 32,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _playHistoryItem(item),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
