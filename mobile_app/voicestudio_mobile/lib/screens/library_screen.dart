import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import '../config/theme.dart';
import '../state/app_state.dart';
import '../models/saved_audio.dart';
import '../widgets/saved_audio_detail_modal.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _searchQuery = '';
  bool _onlyFavorites = false;
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final filtered = state.savedAudios.where((item) {
      if (_onlyFavorites && !item.isFavorite) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesTitle = item.title.toLowerCase().contains(q);
        final matchesText = item.text.toLowerCase().contains(q);
        final matchesProfile = item.profileName.toLowerCase().contains(q);
        return matchesTitle || matchesText || matchesProfile;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Library (Offline)'),
        actions: [
          IconButton(
            icon: Icon(
              _onlyFavorites ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _onlyFavorites ? Colors.amber : AppTheme.textSecondary,
            ),
            tooltip: _onlyFavorites ? 'Show All' : 'Show Favorites Only',
            onPressed: () => setState(() => _onlyFavorites = !_onlyFavorites),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search offline library...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // Count & Filter info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _onlyFavorites ? 'FAVORITES (${filtered.length})' : 'SAVED TAKES (${filtered.length})',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '${state.savedAudios.length} total stored',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // List of saved audios
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _onlyFavorites ? Icons.star_border_rounded : Icons.library_music_outlined,
                            size: 54,
                            color: AppTheme.textMuted,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _onlyFavorites
                                ? 'No favorite takes yet'
                                : (state.savedAudios.isEmpty
                                    ? 'No saved audio in library\nTap the bookmark icon on the audio player to save takes offline!'
                                    : 'No matches found for "$_searchQuery"'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isPlaying = _currentlyPlayingId == item.id;

                      return _LibraryItemCard(
                        item: item,
                        isPlaying: isPlaying,
                        onTap: () => SavedAudioDetailModal.show(context, item),
                        onPlayToggle: () async {
                          if (isPlaying) {
                            await state.audio.pause();
                            setState(() => _currentlyPlayingId = null);
                          } else {
                            final file = File(item.filePath);
                            if (await file.exists()) {
                              setState(() => _currentlyPlayingId = item.id);
                              await state.audio.playFile(file);
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Audio file no longer exists on device storage.'),
                                    backgroundColor: AppTheme.primary,
                                  ),
                                );
                              }
                            }
                          }
                        },
                        onToggleFavorite: () => state.toggleFavoriteAudio(item.id),
                        onDelete: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Audio'),
                              content: Text('Delete "${item.title}" from local library?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            if (_currentlyPlayingId == item.id) {
                              await state.audio.stop();
                              setState(() => _currentlyPlayingId = null);
                            }
                            await state.deleteSavedAudio(item.id);
                          }
                        },
                        onShare: () async {
                          final file = File(item.filePath);
                          if (await file.exists()) {
                            await SharePlus.instance.share(
                              ShareParams(
                                files: [XFile(file.path)],
                                text: '${item.title} (Voice: ${item.profileName})',
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LibraryItemCard extends StatelessWidget {
  final SavedAudio item;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlayToggle;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _LibraryItemCard({
    required this.item,
    required this.isPlaying,
    required this.onTap,
    required this.onPlayToggle,
    required this.onToggleFavorite,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final fileExists = File(item.filePath).existsSync();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPlaying ? AppTheme.surfaceHighlight : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying ? AppTheme.primaryNeon : AppTheme.border,
          width: isPlaying ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play/Pause button
              GestureDetector(
                onTap: onPlayToggle,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isPlaying
                          ? [AppTheme.primaryNeon, AppTheme.primary]
                          : fileExists
                              ? [AppTheme.surfaceElevated, AppTheme.surfaceHighlight]
                              : [AppTheme.surface, AppTheme.surfaceElevated],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : (fileExists ? Icons.play_arrow_rounded : Icons.broken_image_rounded),
                    color: isPlaying
                        ? Colors.white
                        : (fileExists ? AppTheme.primary : AppTheme.textMuted),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and Profile badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accentCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.profileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.accentCyan,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        if (!fileExists) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 11, color: Colors.redAccent),
                                SizedBox(width: 2),
                                Text(
                                  'Missing',
                                  style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (item.duration > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• ${item.duration.toStringAsFixed(1)}s',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              IconButton(
                icon: Icon(
                  item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: item.isFavorite ? Colors.amber : AppTheme.textMuted,
                  size: 20,
                ),
                tooltip: 'Favorite',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleFavorite,
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 18, color: AppTheme.textMuted),
                tooltip: 'Share audio',
                visualDensity: VisualDensity.compact,
                onPressed: onShare,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.textMuted),
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
              ),
            ],
          ),

          if (item.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.open_in_full_rounded, size: 13, color: AppTheme.accentCyan),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
}
