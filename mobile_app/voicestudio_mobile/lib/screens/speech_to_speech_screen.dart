import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/api_client.dart';
import '../services/recorder_service.dart';
import '../state/app_state.dart';
import '../widgets/neon_audio_player.dart';
import '../widgets/voice_selector_card.dart';
import 'library_screen.dart';
import 'voice_clone_screen.dart';

class SpeechToSpeechScreen extends StatefulWidget {
  const SpeechToSpeechScreen({super.key});

  @override
  State<SpeechToSpeechScreen> createState() => _SpeechToSpeechScreenState();
}

class _SpeechToSpeechScreenState extends State<SpeechToSpeechScreen> {
  bool _isRecording = false;
  int _recordSeconds = 0;
  double _currentNormalizedLevel = 0.0;
  Timer? _recordTimer;
  Timer? _ampTimer;
  String? _sourceAudioPath;
  bool _isCleaned = false;
  bool _isCleaning = false;
  bool _matchDuration = true;
  bool _isConverting = false;
  CancelToken? _convertCancelToken;
  ConvertResult? _lastResult;
  RecorderService? _recorder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recorder = context.read<AppState>().recorder;
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _ampTimer?.cancel();
    _convertCancelToken?.cancel();
    if (_isRecording && _recorder != null) {
      _recorder!.stopRecording();
    }
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final state = context.read<AppState>();
    HapticFeedback.lightImpact();

    if (_isRecording) {
      _recordTimer?.cancel();
      _ampTimer?.cancel();
      final path = await state.recorder.stopRecording();
      setState(() {
        _isRecording = false;
        _currentNormalizedLevel = 0.0;
        _sourceAudioPath = path;
        _isCleaned = false;
      });
    } else {
      try {
        await state.recorder.startRecording();
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
          _currentNormalizedLevel = 0.0;
          _sourceAudioPath = null;
          _isCleaned = false;
        });

        _ampTimer = Timer.periodic(const Duration(milliseconds: 100), (t) async {
          if (!mounted || !_isRecording) {
            t.cancel();
            return;
          }
          try {
            final amp = await state.recorder.getAmplitude();
            final db = amp.current.isFinite ? amp.current : -60.0;
            final norm = ((db + 55.0) / 55.0).clamp(0.0, 1.0);
            if (mounted) setState(() => _currentNormalizedLevel = norm);
          } catch (_) {}
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() => _recordSeconds++);
          if (_recordSeconds >= 45) {
            _toggleRecording();
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Greška mikrofona: $e'), backgroundColor: AppTheme.primary),
          );
        }
      }
    }
  }

  Future<void> _pickSourceFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'flac', 'ogg'],
    );
    if (files.isNotEmpty && files.first.path != null) {
      setState(() {
        _sourceAudioPath = files.first.path!;
        _isCleaned = false;
      });
    }
  }

  Future<void> _denoiseSource() async {
    if (_sourceAudioPath == null || _isCleaning) return;
    final state = context.read<AppState>();
    setState(() => _isCleaning = true);
    try {
      final cleaned = await state.api.cleanAudio(File(_sourceAudioPath!));
      if (!mounted) return;
      setState(() {
        _sourceAudioPath = cleaned.path;
        _isCleaned = true;
      });
      await state.audio.playFile(cleaned);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pozadinski šum uspješno uklonjen!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isCleaning = false);
    }
  }

  Future<void> _convertVoice() async {
    final state = context.read<AppState>();
    if (_sourceAudioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Najprije snimite svoj govor ili odaberite audio datoteku.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }
    if (state.selectedProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Odaberite ciljni glasovni profil u koji želite pretvoriti snimku.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    _convertCancelToken?.cancel();
    final token = CancelToken();
    _convertCancelToken = token;

    setState(() => _isConverting = true);
    try {
      final res = await state.api.convertSpeech(
        sourceAudio: File(_sourceAudioPath!),
        profileId: state.selectedProfile!.id,
        matchDuration: _matchDuration,
        cancelToken: token,
      );
      if (!mounted) return;
      setState(() => _lastResult = res);
      await state.audio.playFile(res.audioFile);
      unawaited(state.refreshHistory());
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      if (!msg.contains('prekinut')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech-to-Speech (Promjena glasa)'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Target Voice Selector
          VoiceSelectorCard(
            profiles: state.profiles,
            selectedProfile: state.selectedProfile,
            isLoading: state.isLoadingProfiles,
            onSelect: (p) => state.selectProfile(p),
            onAddVoice: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceCloneScreen()),
              );
            },
          ),
          const SizedBox(height: 20),

          // Step 2: Record or Upload Source Performance
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isRecording ? AppTheme.primaryNeon : AppTheme.border,
                  width: _isRecording ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'IZVORNA IZVEDBA (TVOJ GLAS)',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Snimite rečenicu vlastitim glasom i intonacijom — AI će zadržati ritam i pretvoriti boju glasa u odabrani profil.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 22),

                  GestureDetector(
                    onTap: _toggleRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 84 + (_isRecording ? (_currentNormalizedLevel * 14) : 0),
                      height: 84 + (_isRecording ? (_currentNormalizedLevel * 14) : 0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isRecording
                              ? [AppTheme.primaryNeon, const Color(0xFFFF1E44)]
                              : [AppTheme.surfaceHighlight, AppTheme.surfaceElevated],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isRecording ? Colors.white : AppTheme.borderGlow,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 38,
                        color: _isRecording ? Colors.white : AppTheme.accentCyan,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isRecording
                        ? 'Snimanje... 00:${_recordSeconds.toString().padLeft(2, '0')} / 00:45'
                        : (_sourceAudioPath != null
                            ? 'Snimka spremna za pretvorbu'
                            : 'Dodirnite mikrofon za snimanje izvedbe'),
                    style: TextStyle(
                      color: _isRecording ? AppTheme.primaryNeon : AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: _isRecording ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),

                  if (_isRecording) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 24,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(18, (i) {
                          final threshold = (i + 1) / 18.0;
                          final active = _currentNormalizedLevel >= threshold * 0.85;
                          final barHeight = 6.0 + math.sin((i / 18.0) * math.pi) * 16.0;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 80),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: 4,
                            height: active ? barHeight : 5,
                            decoration: BoxDecoration(
                              color: active ? AppTheme.accentCyan : AppTheme.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _isRecording ? null : _pickSourceFile,
                    icon: const Icon(Icons.upload_file_rounded, size: 17),
                    label: const Text('Ili učitaj postojeću audio snimku'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyan,
                      side: const BorderSide(color: AppTheme.border),
                    ),
                  ),

                  if (_sourceAudioPath != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isCleaned
                              ? AppTheme.accentGreen.withValues(alpha: 0.5)
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isCleaned ? Icons.auto_fix_high_rounded : Icons.audiotrack_rounded,
                            color: _isCleaned ? AppTheme.accentGreen : AppTheme.accentCyan,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isCleaned ? 'Izvorna snimka (AI očišćen šum)' : 'Izvorna snimka spremna',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accentCyan),
                            tooltip: 'Poslušaj izvornu snimku',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => state.audio.playFile(File(_sourceAudioPath!)),
                          ),
                          if (!_isCleaned)
                            TextButton.icon(
                              onPressed: _isCleaning ? null : _denoiseSource,
                              icon: _isCleaning
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                                    )
                                  : const Icon(Icons.cleaning_services_rounded, size: 15),
                              label: Text(_isCleaning ? 'Čistim...' : 'Denoise', style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Uskladi trajanje s mojom snimkom',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Prilagođava brzinu generiranog glasa trajanju tvoje izvorne rečenice.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                    value: _matchDuration,
                    activeThumbColor: AppTheme.accentCyan,
                    onChanged: (v) => setState(() => _matchDuration = v),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isConverting || _sourceAudioPath == null) ? null : _convertVoice,
                          icon: _isConverting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.swap_horiz_rounded, size: 22),
                          label: Text(
                            _isConverting
                                ? 'Pretvaram glas na poslužitelju...'
                                : 'Pretvori u "${state.selectedProfile?.name ?? "odabrani glas"}"',
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                      if (_isConverting) ...[
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: () => _convertCancelToken?.cancel(),
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
          ),

          // Step 3: Result & Recognized Transcript
          if (_lastResult != null) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PREPOZNATI TEKST (WHISPER ASR)',
                      style: TextStyle(
                        color: AppTheme.accentCyan,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _lastResult!.recognizedText,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: NeonAudioPlayer(
                audioService: state.audio,
                currentAudioFile: _lastResult!.audioFile,
                title: 'S2S: ${state.selectedProfile?.name ?? "Klonirani glas"}',
                currentSpeed: state.speed,
                onSpeedChanged: (s) => state.setSpeed(s),
                isSaved: state.savedAudios.any((a) => a.filePath == _lastResult!.audioFile.path),
                onSaveToLibrary: () async {
                  final saved = await state.saveToLibrary(
                    file: _lastResult!.audioFile,
                    text: _lastResult!.recognizedText,
                    profileName: state.selectedProfile?.name ?? 'S2S',
                    duration: _lastResult!.duration,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Spremljeno "${saved.title}" u offline biblioteku!'),
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
            ),
          ],
        ],
      ),
    );
  }
}

