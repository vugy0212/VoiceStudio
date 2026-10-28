import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
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
  String? _downloadingId;
  StreamSubscription<PlayerState>? _playerSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (state.history.isEmpty && !state.isBackendSleeping) {
        state.refreshHistory();
      }
    });
  }

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

  Future<void> _saveToOfflineLibrary(GenerationHistory item) async {
    final state = context.read<AppState>();
    setState(() => _downloadingId = item.id);
    try {
      final saved = await state.saveHistoryItemToLibrary(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Spremljeno u offline biblioteku: "${saved.title}"'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Greška pri preuzimanju: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _shareHistoryItem(GenerationHistory item) async {
    final state = context.read<AppState>();
    setState(() => _downloadingId = item.id);
    try {
      final file = await state.api.downloadAudioFile(item.filename);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: item.text,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Greška pri dijeljenju: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  void _useTextInEditor(GenerationHistory item) {
    HapticFeedback.lightImpact();
    context.read<AppState>().setDraftText(item.text, notify: true);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tekst učitan u glavni editor.'),
        backgroundColor: AppTheme.accentCyan,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Povijest sa poslužitelja'),
        actions: [
          IconButton(
            icon: state.isLoadingHistory
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                  )
                : const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan),
            tooltip: 'Osvježi povijest',
            onPressed: state.isLoadingHistory ? null : () => state.refreshHistory(),
          ),
        ],
      ),
      body: state.history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.history_rounded, size: 32, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.isBackendSleeping
                          ? 'Engine je u Standby režimu (0% GPU)'
                          : 'Još nema generiranih zapisa',
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.isBackendSleeping
                          ? 'Dodirnite gumb za osvježavanje na vrhu ako želite probuditi poslužitelj i dohvatiti povijest.'
                          : 'Govor generiran na računalu ili mobitelu pojavit će se ovdje.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = state.history[index];
                final isPlaying = _currentlyPlayingId == item.id;
                final isDownloading = _downloadingId == item.id;

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
                                  item.profileName ?? 'Klonirani glas',
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_note_rounded, color: AppTheme.accentCyan, size: 22),
                                tooltip: 'Učitaj tekst u editor',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _useTextInEditor(item),
                              ),
                              IconButton(
                                icon: isDownloading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen),
                                      )
                                    : const Icon(Icons.download_for_offline_outlined, color: AppTheme.accentGreen, size: 21),
                                tooltip: 'Spremi u offline biblioteku',
                                visualDensity: VisualDensity.compact,
                                onPressed: isDownloading ? null : () => _saveToOfflineLibrary(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_rounded, color: AppTheme.textSecondary, size: 19),
                                tooltip: 'Podijeli audio',
                                visualDensity: VisualDensity.compact,
                                onPressed: isDownloading ? null : () => _shareHistoryItem(item),
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
