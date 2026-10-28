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

  /// Automatically cleans markdown and punctuation quirks before speech synthesis
  static String cleanTextForSpeech(String text) {
    if (text.isEmpty) return text;
    var out = text;
    out = out.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^\)]+\)'), (m) => m[1] ?? '');
    out = out.replaceAllMapped(
        RegExp(r'`([^`]+)`'), (m) => m[1] ?? '');
    out = out.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    out = out.replaceAllMapped(
        RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1] ?? '');
    out = out.replaceAllMapped(
        RegExp(r'\*([^*]+)\*'), (m) => m[1] ?? '');
    out = out.replaceAllMapped(
        RegExp(r'__([^_]+)__'), (m) => m[1] ?? '');
    out = out.replaceAllMapped(
        RegExp(r'(?<=\s|^)_([^_]+)_(?=\s|[.,:;?!]|$)'), (m) => m[1] ?? '');
    out = out.replaceAll(RegExp(r'\s+([,.:;?!])'), r'$1');
    out = out.replaceAll(RegExp(r'[^\S\n]+'), ' ');
    return out.trim();
  }

  @override
  State<TextInputCard> createState() => _TextInputCardState();
}

class _TextInputCardState extends State<TextInputCard> {
  bool _isPlaying = false;
  bool _manualEditOverride = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  final ScrollController _karaokeScrollController = ScrollController();
  final GlobalKey _karaokeViewportKey = GlobalKey();
  final GlobalKey _activeWordKey = GlobalKey();
  int _lastScrolledWordIdx = -1;

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
            _manualEditOverride = false;
            _lastScrolledWordIdx = -1;
          }
          _isPlaying = nowPlaying;
        });
      });

      _positionSub = audio.positionStream.listen((pos) {
        if (!mounted) return;
        if (_isPlaying) {
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
    _karaokeScrollController.dispose();
    super.dispose();
  }

  /// Scrolls ONLY the internal [_karaokeScrollController] without touching the
  /// outer screen's ListView, preventing any screen jumping on mobile!
  void _scrollInnerKaraokeOnly(int activeIdx) {
    if (activeIdx < 0 || activeIdx == _lastScrolledWordIdx) return;
    _lastScrolledWordIdx = activeIdx;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_karaokeScrollController.hasClients) return;
      final wordBox =
          _activeWordKey.currentContext?.findRenderObject() as RenderBox?;
      final viewportBox =
          _karaokeViewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (wordBox == null || viewportBox == null || !wordBox.attached) return;

      final wordTopInViewport =
          wordBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      final wordBottomInViewport = wordTopInViewport + wordBox.size.height;
      final viewportHeight = viewportBox.size.height;

      // Only scroll if the active word moves below 65% or above 15% of the inner box
      if (wordBottomInViewport > viewportHeight * 0.68 ||
          wordTopInViewport < viewportHeight * 0.12) {
        final currentOffset = _karaokeScrollController.offset;
        final targetOffset = (currentOffset +
                wordTopInViewport -
                (viewportHeight * 0.32))
            .clamp(0.0, _karaokeScrollController.position.maxScrollExtent);

        _karaokeScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      widget.controller.text = TextInputCard.cleanTextForSpeech(data.text!);
    }
  }

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

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: showKaraokeView
                  ? AppTheme.accentCyan.withValues(alpha: 0.75)
                  : const Color(0xFF2E3A52),
              width: 1.3,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header inside card
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                                  ? 'Praćenje glasa'
                                  : 'Tekst za sintezu',
                              style: TextStyle(
                                color: showKaraokeView
                                    ? AppTheme.accentCyan
                                    : AppTheme.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Explicit STOP button while playing
                        if (_isPlaying) ...[
                          GestureDetector(
                            onTap: () async {
                              HapticFeedback.mediumImpact();
                              await appState.audio.stop();
                              await appState.audio.seek(Duration.zero);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.6),
                                  width: 1,
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.stop_rounded,
                                      size: 14, color: Colors.redAccent),
                                  SizedBox(width: 3),
                                  Text(
                                    'Stop',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        // Toggle Karaoke / Uredi
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
                                  _lastScrolledWordIdx = -1;
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
                        if (!showKaraokeView) ...[
                          GestureDetector(
                            onTap: _pasteClipboard,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
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
                          const SizedBox(width: 6),
                        ],
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
                        if (text.isNotEmpty && !showKaraokeView) ...[
                          const SizedBox(width: 2),
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

              // Body: Fixed-height Karaoke view (zero layout shift!) OR TextField
              if (showKaraokeView)
                _buildKaraokeBody(context, text, wordCount, appState)
              else
                SizedBox(
                  height: 156,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: TextField(
                      controller: widget.controller,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
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
                ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        showKaraokeView
                            ? 'Dodirnite riječ za skok • "Stop" za zaustavljanje'
                            : '$wordCount riječi • $charCount znakova',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    ),
                    if (charCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '~${(wordCount / 2.5).ceil()}s procjena',
                        style: const TextStyle(
                          color: AppTheme.accentCyan,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
    final effectiveTotalMs = _duration.inMilliseconds > 200
        ? _duration.inMilliseconds
        : math.max(1200, (wordCount / 2.6 * 1000).round());

    final progress =
        (_position.inMilliseconds / effectiveTotalMs).clamp(0.0, 1.0);

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

    // Scroll ONLY the internal ScrollController (never the parent screen!)
    _scrollInnerKaraokeOnly(activeIdx);

    return SizedBox(
      key: _karaokeViewportKey,
      height: 156,
      child: SingleChildScrollView(
        controller: _karaokeScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 4,
          runSpacing: 6,
          children: List.generate(tokens.length, (idx) {
            final token = tokens[idx];
            if (token.isNewline) {
              return const SizedBox(width: double.infinity, height: 4);
            }

            final isCurrent = idx == activeIdx;
            final isSpoken = idx < activeIdx;

            // Constant padding and constant fontWeight prevent any line reflow or jumping!
            return GestureDetector(
              key: isCurrent ? _activeWordKey : null,
              onTap: () {
                HapticFeedback.selectionClick();
                final targetMs =
                    (token.startFraction * effectiveTotalMs).round();
                appState.audio.seek(Duration(milliseconds: targetMs));
                if (!appState.audio.isPlaying) {
                  appState.audio.resume();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.accentCyan
                      : (isSpoken
                          ? AppTheme.accentCyan.withValues(alpha: 0.12)
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  token.text,
                  style: TextStyle(
                    color: isCurrent
                        ? const Color(0xFF071018)
                        : (isSpoken
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
