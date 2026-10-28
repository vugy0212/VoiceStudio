import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/voice_profile.dart';
import '../state/app_state.dart';
import '../utils/wav_utils.dart';
import '../widgets/neon_audio_player.dart';
import 'library_screen.dart';

class DialogueLineItem {
  VoiceProfile? profile;
  final TextEditingController textController;
  int pauseMsAfter;
  File? renderedWav;

  DialogueLineItem({
    required this.profile,
    String initialText = '',
    this.pauseMsAfter = 350,
  }) : textController = TextEditingController(text: initialText);

  void dispose() {
    textController.dispose();
  }
}

class DialogueStudioScreen extends StatefulWidget {
  const DialogueStudioScreen({super.key});

  @override
  State<DialogueStudioScreen> createState() => _DialogueStudioScreenState();
}

class _DialogueStudioScreenState extends State<DialogueStudioScreen> {
  final List<DialogueLineItem> _lines = [];
  bool _isRendering = false;
  int _currentRenderingIndex = 0;
  CancelToken? _cancelToken;
  File? _stitchedAudioFile;
  double _stitchedDuration = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profiles = context.read<AppState>().profiles;
      final p1 = profiles.isNotEmpty ? profiles.first : null;
      final p2 = profiles.length > 1 ? profiles[1] : p1;
      setState(() {
        _lines.add(DialogueLineItem(profile: p1, initialText: 'Bok! Jesi li isprobao novi višeglasni dijalog u VoiceStudiu?'));
        _lines.add(DialogueLineItem(profile: p2, initialText: 'Jesam! Svaka replika može imati svoj glasovni profil i pauzu.'));
      });
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    final profiles = context.read<AppState>().profiles;
    VoiceProfile? nextProfile = profiles.isNotEmpty ? profiles.first : null;
    if (_lines.isNotEmpty && profiles.length > 1) {
      final lastProfileId = _lines.last.profile?.id;
      nextProfile = profiles.firstWhere(
        (p) => p.id != lastProfileId,
        orElse: () => profiles.first,
      );
    }
    setState(() {
      _lines.add(DialogueLineItem(profile: nextProfile));
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 1) return;
    setState(() {
      final removed = _lines.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _showScriptImportModal() async {
    final controller = TextEditingController();
    final state = context.read<AppState>();
    final profiles = state.profiles;

    final imported = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Uvezi skriptu dijaloga',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Unesite svaku repliku u novi red u formatu "Ime: Tekst replike". Imena govornika automatski će se povezati s vašim profilima.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 7,
              minLines: 4,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
              decoration: const InputDecoration(
                hintText: 'Ana: Dobar dan, kako vam mogu pomoći?\nMarko: Tražim informacije o novom projektu.',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Odustani'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  child: const Text('Rasporedi u replike'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (imported != null && imported.trim().isNotEmpty) {
      final rawLines = imported.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (rawLines.isEmpty) return;

      final Map<String, VoiceProfile?> speakerMap = {};
      int nextProfileIdx = 0;

      final List<DialogueLineItem> parsed = [];
      for (final raw in rawLines) {
        final colonIdx = raw.indexOf(':');
        if (colonIdx > 0 && colonIdx < 28) {
          final speaker = raw.substring(0, colonIdx).trim();
          final speech = raw.substring(colonIdx + 1).trim();
          if (speech.isEmpty) continue;

          if (!speakerMap.containsKey(speaker.toLowerCase())) {
            // Match by profile name if exists, otherwise round-robin
            final match = profiles.where(
              (p) => p.name.toLowerCase().contains(speaker.toLowerCase()) ||
                  speaker.toLowerCase().contains(p.name.toLowerCase()),
            );
            if (match.isNotEmpty) {
              speakerMap[speaker.toLowerCase()] = match.first;
            } else if (profiles.isNotEmpty) {
              speakerMap[speaker.toLowerCase()] = profiles[nextProfileIdx % profiles.length];
              nextProfileIdx++;
            } else {
              speakerMap[speaker.toLowerCase()] = null;
            }
          }
          parsed.add(
            DialogueLineItem(
              profile: speakerMap[speaker.toLowerCase()],
              initialText: speech,
            ),
          );
        } else {
          parsed.add(
            DialogueLineItem(
              profile: profiles.isNotEmpty ? profiles[nextProfileIdx % profiles.length] : null,
              initialText: raw,
            ),
          );
        }
      }

      if (parsed.isNotEmpty) {
        for (final old in _lines) {
          old.dispose();
        }
        setState(() {
          _lines
            ..clear()
            ..addAll(parsed);
        });
      }
    }
  }

  Future<void> _renderFullDialogue() async {
    final validLines = _lines.where((l) => l.textController.text.trim().isNotEmpty).toList();
    if (validLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dodajte barem jednu repliku s tekstom.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    final state = context.read<AppState>();
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;

    setState(() {
      _isRendering = true;
      _currentRenderingIndex = 0;
    });

    try {
      final List<File> wavSegments = [];
      final List<int> pauses = [];

      for (int i = 0; i < validLines.length; i++) {
        if (token.isCancelled) throw Exception('Generiranje dijaloga prekinuto.');
        setState(() => _currentRenderingIndex = i + 1);

        final line = validLines[i];
        final res = await state.api.generateSpeech(
          text: line.textController.text.trim(),
          profileId: line.profile?.id ?? state.selectedProfile?.id,
          speed: state.speed,
          language: state.language,
          instruct: state.instruct,
          steps: state.steps,
          guidanceScale: state.guidanceScale,
          cancelToken: token,
        );
        line.renderedWav = res.audioFile;
        wavSegments.add(res.audioFile);
        pauses.add(line.pauseMsAfter);
      }

      final stitched = await WavUtils.stitchWavFiles(
        wavSegments,
        pausesMsAfter: pauses,
        prefix: 'dialogue',
      );

      if (!mounted) return;
      setState(() {
        _stitchedAudioFile = stitched.file;
        _stitchedDuration = stitched.durationSeconds;
      });
      await state.audio.playFile(stitched.file);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      if (!msg.contains('prekinut')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isRendering = false);
    }
  }

  String _compileScriptText() {
    return _lines
        .where((l) => l.textController.text.trim().isNotEmpty)
        .map((l) => '${l.profile?.name ?? "Glas"}: ${l.textController.text.trim()}')
        .join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profiles = state.profiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Višeglasni Dijalog Studio'),
        actions: [
          TextButton.icon(
            onPressed: _isRendering ? null : _showScriptImportModal,
            icon: const Icon(Icons.paste_rounded, size: 17, color: AppTheme.accentCyan),
            label: const Text('Uvezi skriptu', style: TextStyle(color: AppTheme.accentCyan, fontSize: 12.5)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _lines.length + 1,
              itemBuilder: (context, index) {
                if (index == _lines.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 20),
                    child: OutlinedButton.icon(
                      onPressed: _isRendering ? null : _addLine,
                      icon: const Icon(Icons.add_comment_rounded, size: 18),
                      label: const Text('Dodaj novu repliku'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentCyan,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  );
                }

                final item = _lines[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#${index + 1}',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Speaker Dropdown
                          Expanded(
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: profiles.any((p) => p.id == item.profile?.id)
                                      ? item.profile?.id
                                      : (profiles.isNotEmpty ? profiles.first.id : null),
                                  dropdownColor: AppTheme.surfaceElevated,
                                  hint: const Text(
                                    'Odaberi glas',
                                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                  ),
                                  style: const TextStyle(
                                    color: AppTheme.accentCyan,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  items: profiles.map((p) {
                                    return DropdownMenuItem<String>(
                                      value: p.id,
                                      child: Text(p.name, overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  onChanged: (id) {
                                    if (id != null) {
                                      setState(() {
                                        item.profile = profiles.firstWhere((p) => p.id == id);
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Pause selector
                          PopupMenuButton<int>(
                            tooltip: 'Pauza nakon replike',
                            color: AppTheme.surfaceElevated,
                            initialValue: item.pauseMsAfter,
                            onSelected: (ms) => setState(() => item.pauseMsAfter = ms),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 150, child: Text('Brzi prijelaz (0.15s)')),
                              PopupMenuItem(value: 350, child: Text('Prirodna pauza (0.35s)')),
                              PopupMenuItem(value: 700, child: Text('Duža pauza (0.7s)')),
                              PopupMenuItem(value: 1200, child: Text('Dramska pauza (1.2s)')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_outlined, size: 13, color: AppTheme.textMuted),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${(item.pauseMsAfter / 1000).toStringAsFixed(1)}s',
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_lines.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _removeLine(index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: item.textController,
                        maxLines: 3,
                        minLines: 2,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Tekst replike za ${item.profile?.name ?? "ovog govornika"}...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom Action Bar & Stitched Audio Player
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_stitchedAudioFile != null) ...[
                  NeonAudioPlayer(
                    audioService: state.audio,
                    currentAudioFile: _stitchedAudioFile,
                    title: 'Dijalog (${_lines.length} replika)',
                    currentSpeed: state.speed,
                    onSpeedChanged: (s) => state.setSpeed(s),
                    isSaved: state.savedAudios.any((a) => a.filePath == _stitchedAudioFile!.path),
                    onSaveToLibrary: () async {
                      final saved = await state.saveToLibrary(
                        file: _stitchedAudioFile!,
                        text: _compileScriptText(),
                        profileName: 'Višeglasni dijalog',
                        duration: _stitchedDuration,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dijalog "${saved.title}" spremljen u biblioteku!'),
                            backgroundColor: AppTheme.accentGreen,
                            action: SnackBarAction(
                              label: 'OTVORI',
                              textColor: Colors.white,
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const LibraryScreen()),
                                );
                              },
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRendering
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                _renderFullDialogue();
                              },
                        icon: _isRendering
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.forum_rounded, size: 20),
                        label: Text(
                          _isRendering
                              ? 'Sintetiziram repliku $_currentRenderingIndex / ${_lines.length}...'
                              : 'Generiraj i spoji cijeli dijalog (${_lines.length})',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                    if (_isRendering) ...[
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => _cancelToken?.cancel(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.all(14),
                        ),
                        icon: const Icon(Icons.stop_rounded),
                      ),
                    ],
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

