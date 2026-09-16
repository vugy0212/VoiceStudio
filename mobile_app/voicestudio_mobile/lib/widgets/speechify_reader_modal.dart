import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _chunks = _splitText(widget.fullText);
  }

  List<String> _splitText(String text) {
    final rawLines = text.split(RegExp(r'\n+'));
    final List<String> result = [];
    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // If a paragraph is very long (> 500 chars), split at sentence boundaries
      if (trimmed.length > 500) {
        final sentences = trimmed.split(RegExp(r'(?<=[.?!])\s+'));
        String buffer = '';
        for (final s in sentences) {
          if ('$buffer $s'.length > 400 && buffer.isNotEmpty) {
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

  void _readCurrentParagraph() {
    if (_chunks.isEmpty) return;
    final state = context.read<AppState>();
    final currentText = _chunks[_currentIndex];
    state.generateSpeech(currentText);
  }

  void _nextParagraph() {
    if (_currentIndex < _chunks.length - 1) {
      setState(() => _currentIndex++);
      _readCurrentParagraph();
    }
  }

  void _previousParagraph() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _readCurrentParagraph();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.auto_stories_rounded, color: AppTheme.primary, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Speechify Reader Mode',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Chunk ${_currentIndex + 1} of ${_chunks.length} • Voice: ${state.selectedProfile?.name ?? "Default"}',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Paragraph Reader Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _chunks.isNotEmpty ? _chunks[_currentIndex] : '',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16.5,
                      height: 1.6,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Controls & Player Bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nav & Play Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Previous
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 32),
                      color: _currentIndex > 0 ? AppTheme.accentCyan : AppTheme.border,
                      onPressed: _currentIndex > 0 ? _previousParagraph : null,
                    ),

                    // Play / Synthesize Current
                    GestureDetector(
                      onTap: state.isGenerating ? null : _readCurrentParagraph,
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
                              color: AppTheme.primaryNeon.withValues(alpha: 0.4),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Center(
                          child: state.isGenerating
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                    ),

                    // Next
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 32),
                      color: _currentIndex < _chunks.length - 1 ? AppTheme.accentCyan : AppTheme.border,
                      onPressed: _currentIndex < _chunks.length - 1 ? _nextParagraph : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
