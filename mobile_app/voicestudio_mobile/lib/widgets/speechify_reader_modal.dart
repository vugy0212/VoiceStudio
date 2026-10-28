import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';

class SpeechifyReaderModal extends StatefulWidget {
  final String fullText;

  const SpeechifyReaderModal({super.key, required this.fullText});

  static void show(BuildContext context, String text) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpeechifyReaderModal(fullText: text),
    );
  }

  @override
  State<SpeechifyReaderModal> createState() => _SpeechifyReaderModalState();
}

class _SpeechifyReaderModalState extends State<SpeechifyReaderModal> {
  late List<String> _chunks;
  int _currentIndex = 0;
  bool _autoAdvance = true;
  bool _isSynthesizingCurrent = false;
  bool _isPrefetchingNext = false;

  final Map<int, GenerateResult> _cache = {};
  CancelToken? _prefetchCancelToken;
  StreamSubscription<PlayerState>? _playerSub;
  final GlobalKey _activeWordKey = GlobalKey();
  int _lastScrolledWordIdx = -1;

  @override
  void initState() {
    super.initState();
    _chunks = _splitText(widget.fullText);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audio = context.read<AppState>().audio;
      _playerSub = audio.playerStateStream.listen((playerState) {
        if (!mounted) return;
        if (playerState.processingState == ProcessingState.completed &&
            !_isSynthesizingCurrent &&
            _autoAdvance &&
            _currentIndex < _chunks.length - 1) {
          _nextParagraph();
        }
      });
      _readCurrentParagraph();
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _prefetchCancelToken?.cancel();
    super.dispose();
  }

  List<String> _splitText(String text) {
    final rawLines = text.split(RegExp(r'\n+'));
    final List<String> result = [];
    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length > 420) {
        final sentences = trimmed.split(RegExp(r'(?<=[.?!])\s+'));
        String buffer = '';
        for (final s in sentences) {
          if ('$buffer $s'.length > 360 && buffer.isNotEmpty) {
            result.add(buffer.trim());
            buffer = s;
          } else {
            buffer = buffer.isEmpty ? s : '$buffer $s';
          }
        }
        if (buffer.isNotEmpty) result.add(buffer.trim());
      } else {
        result.add(trimmed);
      }
    }
    return result.isEmpty ? [text] : result;
  }

  Future<void> _readCurrentParagraph() async {
    if (_chunks.isEmpty || !mounted) return;
    final state = context.read<AppState>();
    final index = _currentIndex;

    final cached = _cache[index];
    if (cached != null && await cached.audioFile.exists()) {
      await state.audio.playFile(cached.audioFile);
      _prefetchNextParagraph(index + 1);
      return;
    }

    setState(() => _isSynthesizingCurrent = true);
    try {
      final result = await state.api.generateSpeech(
        text: _chunks[index],
        profileId: state.selectedProfile?.id,
        speed: state.speed,
        language: state.language,
        instruct: state.instruct,
        steps: state.steps,
        guidanceScale: state.guidanceScale,
      );
      if (!mounted) return;
      _cache[index] = result;
      setState(() => _isSynthesizingCurrent = false);

      if (_currentIndex == index) {
        await state.audio.playFile(result.audioFile);
        _prefetchNextParagraph(index + 1);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSynthesizingCurrent = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Greška pri čitanju odlomka: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _prefetchNextParagraph(int nextIndex) async {
    if (nextIndex >= _chunks.length ||
        _cache.containsKey(nextIndex) ||
        _isPrefetchingNext ||
        !mounted) {
      return;
    }
    final state = context.read<AppState>();
    _prefetchCancelToken?.cancel();
    final token = CancelToken();
    _prefetchCancelToken = token;

    setState(() => _isPrefetchingNext = true);
    try {
      final res = await state.api.generateSpeech(
        text: _chunks[nextIndex],
        profileId: state.selectedProfile?.id,
        speed: state.speed,
        language: state.language,
        instruct: state.instruct,
        steps: state.steps,
        guidanceScale: state.guidanceScale,
        cancelToken: token,
      );
      if (!mounted) return;
      _cache[nextIndex] = res;
    } catch (_) {
      // Non-critical background prefetch error
    } finally {
      if (mounted) setState(() => _isPrefetchingNext = false);
    }
  }

  void _nextParagraph() {
    if (_currentIndex < _chunks.length - 1) {
      setState(() {
        _currentIndex++;
        _lastScrolledWordIdx = -1;
      });
      _readCurrentParagraph();
    }
  }

  void _previousParagraph() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _lastScrolledWordIdx = -1;
      });
      _readCurrentParagraph();
    }
  }

  Widget _buildWordSyncedParagraph(String paragraphText, AppState state) {
    final words = paragraphText
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const SizedBox.shrink();

    final weights = words.map((w) {
      final cleanLen =
          w.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').length;
      double weight = math.max(2, cleanLen).toDouble();
      if (RegExp(r'[.!?…]+$').hasMatch(w)) {
        weight += 6.0;
      } else if (RegExp(r'[,;:—\-]+$').hasMatch(w)) {
        weight += 3.0;
      }
      return weight;
    }).toList();

    final totalWeight = weights.fold<double>(0.0, (a, b) => a + b);

    return StreamBuilder<Duration>(
      stream: state.audio.positionStream,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? state.audio.currentPosition;
        final dur = state.audio.totalDuration;
        final totalMs = (dur != null && dur.inMilliseconds > 200)
            ? dur.inMilliseconds
            : math.max(1200, (words.length / 2.6 * 1000).round());
        final progress = (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);

        int activeIdx = -1;
        double cum = 0.0;
        final starts = <double>[];
        for (int i = 0; i < words.length; i++) {
          final s = cum / totalWeight;
          starts.add(s);
          cum += weights[i];
          final e = cum / totalWeight;
          if (activeIdx == -1 && progress >= s && progress <= e + 0.002) {
            activeIdx = i;
          }
        }

        if (activeIdx >= 0 && activeIdx != _lastScrolledWordIdx) {
          _lastScrolledWordIdx = activeIdx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final ctx = _activeWordKey.currentContext;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                alignment: 0.4,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }

        return Wrap(
          spacing: 5,
          runSpacing: 6,
          children: List.generate(words.length, (wIdx) {
            final isWordCurrent =
                wIdx == activeIdx && !_isSynthesizingCurrent;
            final isWordSpoken =
                wIdx < activeIdx && !_isSynthesizingCurrent;

            return GestureDetector(
              key: isWordCurrent ? _activeWordKey : null,
              onTap: () {
                HapticFeedback.selectionClick();
                final targetMs = (starts[wIdx] * totalMs).round();
                state.audio.seek(Duration(milliseconds: targetMs));
                if (!state.audio.isPlaying) {
                  state.audio.resume();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: EdgeInsets.symmetric(
                  horizontal: isWordCurrent ? 6 : 2,
                  vertical: isWordCurrent ? 2 : 1,
                ),
                decoration: BoxDecoration(
                  color: isWordCurrent
                      ? AppTheme.accentCyan
                      : (isWordSpoken
                          ? AppTheme.accentCyan.withValues(alpha: 0.10)
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  words[wIdx],
                  style: TextStyle(
                    color: isWordCurrent
                        ? const Color(0xFF071018)
                        : (isWordSpoken
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary),
                    fontSize: 16,
                    fontWeight: isWordCurrent
                        ? FontWeight.w800
                        : (isWordSpoken ? FontWeight.w600 : FontWeight.w500),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
      child: Column(
        children: [
          // Drag handle & Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.auto_stories_rounded,
                                color: AppTheme.primary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pametni Čitač (Reader)',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Odlomak ${_currentIndex + 1} od ${_chunks.length} • ${state.selectedProfile?.name ?? "Zadani glas"}'
                                  '${_isPrefetchingNext ? " • ⚡ Spremanje idućeg..." : (_cache.containsKey(_currentIndex + 1) ? " • ✓ Idući spreman" : "")}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppTheme.textMuted, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilterChip(
                      label: const Text('Auto',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                      selected: _autoAdvance,
                      onSelected: (v) => setState(() => _autoAdvance = v),
                      selectedColor:
                          AppTheme.accentCyan.withValues(alpha: 0.25),
                      checkmarkColor: AppTheme.accentCyan,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppTheme.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Paragraph List / Reader Card
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _chunks.length,
              itemBuilder: (context, idx) {
                final isCurrent = idx == _currentIndex;
                final isCached = _cache.containsKey(idx);
                return GestureDetector(
                  onTap: () {
                    setState(() => _currentIndex = idx);
                    _readCurrentParagraph();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppTheme.surfaceHighlight
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            isCurrent ? AppTheme.primaryNeon : AppTheme.border,
                        width: isCurrent ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isCurrent
                                  ? 'ODLOMAK ${idx + 1} • PRAĆENJE RIJEČI'
                                  : 'ODLOMAK ${idx + 1}',
                              style: TextStyle(
                                color: isCurrent
                                    ? AppTheme.accentCyan
                                    : AppTheme.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            if (isCached)
                              const Icon(Icons.bolt_rounded,
                                  size: 15, color: AppTheme.accentGreen),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (isCurrent)
                          _buildWordSyncedParagraph(_chunks[idx], state)
                        else
                          Text(
                            _chunks[idx],
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              height: 1.55,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Controls & Player Bar
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: StreamBuilder<PlayerState>(
              stream: state.audio.playerStateStream,
              builder: (context, snap) {
                final isPlaying = snap.data?.playing ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.skip_previous_rounded, size: 32),
                      color: _currentIndex > 0
                          ? AppTheme.accentCyan
                          : AppTheme.border,
                      onPressed:
                          _currentIndex > 0 ? _previousParagraph : null,
                    ),
                    GestureDetector(
                      onTap: _isSynthesizingCurrent
                          ? null
                          : () {
                              if (isPlaying) {
                                state.audio.pause();
                              } else {
                                _readCurrentParagraph();
                              }
                            },
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primaryNeon, AppTheme.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.primaryNeon.withValues(alpha: 0.4),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isSynthesizingCurrent
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white),
                                )
                              : Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 32),
                      color: _currentIndex < _chunks.length - 1
                          ? AppTheme.accentCyan
                          : AppTheme.border,
                      onPressed: _currentIndex < _chunks.length - 1
                          ? _nextParagraph
                          : null,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
