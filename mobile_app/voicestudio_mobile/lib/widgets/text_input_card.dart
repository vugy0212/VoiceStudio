import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../state/app_state.dart';

class _WordTimingToken {
  final String text;
  final bool isNewline;
  final double startFraction;
  final double endFraction;

  const _WordTimingToken({
    required this.text,
    this.isNewline = false,
    required this.startFraction,
    required this.endFraction,
  });
}

class TextInputCard extends StatefulWidget {
  final TextEditingController controller;
  final String selectedLanguage;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onClear;

  const TextInputCard({
    super.key,
    required this.controller,
    required this.selectedLanguage,
    required this.onLanguageChanged,
    required this.onClear,
  });

  @override
  State<TextInputCard> createState() => _TextInputCardState();
}

class _TextInputCardState extends State<TextInputCard> {
  bool _isPlaying = false;
  bool _manualEditOverride = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audio = context.read<AppState>().audio;
      _isPlaying = audio.isPlaying;
      _position = audio.currentPosition;
      _duration = audio.totalDuration ?? Duration.zero;

      _playerStateSub = audio.playerStateStream.listen((state) {
        if (!mounted) return;
        final nowPlaying =
            state.playing && state.processingState != ProcessingState.completed;
        setState(() {
          if (nowPlaying && !_isPlaying) {
            // Automatically enter Karaoke follow mode whenever playback starts
            _manualEditOverride = false;
          }
          _isPlaying = nowPlaying;
        });
      });

      _positionSub = audio.positionStream.listen((pos) {
        if (!mounted) return;
        if (_isPlaying || !_manualEditOverride) {
          setState(() => _position = pos);
        }
      });

      _durationSub = audio.durationStream.listen((dur) {
        if (!mounted) return;
        setState(() => _duration = dur ?? Duration.zero);
      });
    });
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      widget.controller.text = data.text!;
    }
  }

  /// Tokenizes [text] into words and line breaks with phonetic speaking weights
  /// so each word maps to a [startFraction, endFraction] interval of the audio.
  List<_WordTimingToken> _buildWordTimings(String text) {
    final lines = text.split('\n');
    final rawWords = <String>[];
    final weights = <double>[];

    for (int l = 0; l < lines.length; l++) {
      final lineWords = lines[l]
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      for (final word in lineWords) {
        rawWords.add(word);
        final cleanLen =
            word.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').length;
        double weight = math.max(2, cleanLen).toDouble();
        if (RegExp(r'[.!?…]+$').hasMatch(word)) {
          weight += 6.0;
        } else if (RegExp(r'[,;:—\-]+$').hasMatch(word)) {
          weight += 3.0;
        }
        weights.add(weight);
      }
      if (l < lines.length - 1 && lineWords.isNotEmpty) {
        rawWords.add('\n');
        weights.add(2.5);
      }
    }

    final totalWeight = weights.fold<double>(0.0, (acc, w) => acc + w);
    if (totalWeight <= 0) return const [];

    final tokens = <_WordTimingToken>[];
    double cumulative = 0.0;
    for (int i = 0; i < rawWords.length; i++) {
      final w = weights[i];
      final start = cumulative / totalWeight;
      cumulative += w;
      final end = cumulative / totalWeight;
      tokens.add(
        _WordTimingToken(
          text: rawWords[i],
          isNewline: rawWords[i] == '\n',
          startFraction: start,
          endFraction: end,
        ),
      );
    }
    return tokens;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final hasAudioReady = appState.lastGeneration != null;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final text = value.text;
        final wordCount =
            text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
        final charCount = text.length;

        final showKaraokeView =
            text.trim().isNotEmpty && _isPlaying && !_manualEditOverride;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: showKaraokeView
                  ? AppTheme.accentCyan.withValues(alpha: 0.75)
                  : const Color(0xFF2E3A52),
              width: showKaraokeView ? 1.5 : 1.2,
            ),
            boxShadow: showKaraokeView
                ? [
                    BoxShadow(
                      color: AppTheme.accentCyan.withValues(alpha: 0.14),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header inside card
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (showKaraokeView) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.accentCyan,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          Flexible(
                            child: Text(
                              showKaraokeView
                                  ? 'Praćenje glasa uživo'
                                  : 'Tekst za sintezu',
                              style: TextStyle(
                                color: showKaraokeView
                                    ? AppTheme.accentCyan
                                    : AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Toggle between Karaoke follow & Text Edit while playing / audio available
                        if ((_isPlaying || hasAudioReady) &&
                            text.trim().isNotEmpty) ...[
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (showKaraokeView) {
                                  _manualEditOverride = true;
                                } else {
                                  _manualEditOverride = false;
                                  if (!_isPlaying && hasAudioReady) {
                                    appState.audio.resume();
                                  }
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: showKaraokeView
                                    ? AppTheme.accentCyan
                                        .withValues(alpha: 0.18)
                                    : const Color(0xFF1E283C),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: showKaraokeView
                                      ? AppTheme.accentCyan
                                      : const Color(0xFF33415C),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    showKaraokeView
                                        ? Icons.edit_note_rounded
                                        : Icons.lyrics_rounded,
                                    size: 13,
                                    color: AppTheme.accentCyan,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    showKaraokeView ? 'Uredi' : 'Karaoke',
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        // Paste Button (when editing)
                        if (!showKaraokeView) ...[
                          GestureDetector(
                            onTap: _pasteClipboard,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E283C),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFF33415C), width: 1),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.content_paste_rounded,
                                      size: 13, color: AppTheme.accentCyan),
                                  SizedBox(width: 4),
                                  Text(
                                    'Zalijepi',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Language dropdown selector
                        Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: widget.selectedLanguage,
                              dropdownColor: AppTheme.surfaceElevated,
                              icon: const Icon(Icons.arrow_drop_down,
                                  size: 16, color: AppTheme.textSecondary),
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              items: AppConstants.availableLanguages.map((lang) {
                                return DropdownMenuItem(
                                  value: lang,
                                  child: Text(lang),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) widget.onLanguageChanged(val);
                              },
                            ),
                          ),
                        ),
                        // Clear Button
                        if (text.isNotEmpty && !showKaraokeView) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                size: 17, color: AppTheme.textMuted),
                            tooltip: 'Očisti tekst',
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.onClear,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.border),

              // Body: Live Karaoke Word-by-Word Highlight OR Standard TextField
              if (showKaraokeView)
                _buildKaraokeBody(context, text, wordCount, appState)
              else
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: TextField(
                    controller: widget.controller,
                    maxLines: 7,
                    minLines: 4,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          'Unesite ili zalijepite tekst za generiranje prirodnog govora...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),

              // Footer with character & word counts or Karaoke hint
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      showKaraokeView
                          ? 'Dodirnite bilo koju riječ za skok u reprodukciji'
                          : '$wordCount riječi • $charCount znakova',
                      style: TextStyle(
                        color: showKaraokeView
                            ? AppTheme.accentCyan.withValues(alpha: 0.9)
                            : AppTheme.textMuted,
                        fontSize: 11.5,
                        fontWeight: showKaraokeView
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (charCount > 0)
                      Text(
                        '~${(wordCount / 2.5).ceil()}s procjena',
                        style: const TextStyle(
                          color: AppTheme.accentCyan,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKaraokeBody(
    BuildContext context,
    String text,
    int wordCount,
    AppState appState,
  ) {
    final tokens = _buildWordTimings(text);
    // Estimate total duration if player duration isn't reported yet (e.g. during chunk streaming)
    final effectiveTotalMs = _duration.inMilliseconds > 200
        ? _duration.inMilliseconds
        : math.max(1200, (wordCount / 2.6 * 1000).round());

    final progress = (_position.inMilliseconds / effectiveTotalMs).clamp(0.0, 1.0);

    int activeIdx = -1;
    for (int i = 0; i < tokens.length; i++) {
      if (tokens[i].isNewline) continue;
      if (progress >= tokens[i].startFraction &&
          progress <= tokens[i].endFraction + 0.002) {
        activeIdx = i;
        break;
      }
    }
    if (activeIdx == -1 && tokens.isNotEmpty && progress > 0) {
      activeIdx = tokens.length - 1;
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 110, maxHeight: 210),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 5,
          runSpacing: 7,
          children: List.generate(tokens.length, (idx) {
            final token = tokens[idx];
            if (token.isNewline) {
              return const SizedBox(width: double.infinity, height: 4);
            }

            final isCurrent = idx == activeIdx;
            final isSpoken = idx < activeIdx;

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                final targetMs =
                    (token.startFraction * effectiveTotalMs).round();
                appState.audio.seek(Duration(milliseconds: targetMs));
                if (!appState.audio.isPlaying) {
                  appState.audio.resume();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                padding: EdgeInsets.symmetric(
                  horizontal: isCurrent ? 7 : 3,
                  vertical: isCurrent ? 3 : 2,
                ),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.accentCyan
                      : (isSpoken
                          ? AppTheme.accentCyan.withValues(alpha: 0.10)
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppTheme.accentCyan.withValues(alpha: 0.45),
                            blurRadius: 10,
                            spreadRadius: 0.5,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  token.text,
                  style: TextStyle(
                    color: isCurrent
                        ? const Color(0xFF071018)
                        : (isSpoken
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary),
                    fontSize: 15.5,
                    fontWeight: isCurrent
                        ? FontWeight.w800
                        : (isSpoken ? FontWeight.w600 : FontWeight.w400),
                    height: 1.3,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
