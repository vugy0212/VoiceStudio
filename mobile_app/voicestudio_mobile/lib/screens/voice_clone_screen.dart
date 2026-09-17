import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../state/app_state.dart';
import '../models/voice_profile.dart';
import '../services/recorder_service.dart';

class VoiceCloneScreen extends StatefulWidget {
  const VoiceCloneScreen({super.key});

  @override
  State<VoiceCloneScreen> createState() => _VoiceCloneScreenState();
}

class _VoiceCloneScreenState extends State<VoiceCloneScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordedFilePath;
  bool _isSaving = false;
  String? _previewingProfileId;
  RecorderService? _recorder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recorder = context.read<AppState>().recorder;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _recordTimer?.cancel();
    if (_isRecording && _recorder != null) {
      _recorder!.stopRecording();
    }
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final state = context.read<AppState>();
    HapticFeedback.lightImpact();

    if (_isRecording) {
      // Stop recording
      _recordTimer?.cancel();
      final path = await state.recorder.stopRecording();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });
      if (path != null) {
        // Auto-play preview
        await state.audio.playFile(File(path));
      }
    } else {
      // Start recording
      try {
        await state.recorder.startRecording();
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
          _recordedFilePath = null;
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            _recordSeconds++;
          });
          // Auto-stop at 20 seconds maximum (optimal clone duration is 5-15s)
          if (_recordSeconds >= 20) {
            _toggleRecording();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dosegnut maksimalni limit snimanja (20s). Snimka spremljena.'),
                backgroundColor: AppTheme.accentCyan,
              ),
            );
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Microphone error: $e'),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickAudioFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'flac', 'ogg'],
    );

    if (files.isNotEmpty && files.first.path != null) {
      final path = files.first.path!;
      setState(() {
        _recordedFilePath = path;
      });
      if (mounted) {
        final state = context.read<AppState>();
        await state.audio.playFile(File(path));
      }
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a voice profile name'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    if (_recordedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please record audio or select an audio file first'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final state = context.read<AppState>();

    try {
      final profile = await state.createProfile(
        name: name,
        audioPath: _recordedFilePath!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice profile "${profile.name}" created successfully!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _playProfileSample(VoiceProfile profile) async {
    final state = context.read<AppState>();
    final audioUrl = state.api.getProfileAudioUrl(profile.id);
    final headers = state.api.getAuthHeaders();

    setState(() => _previewingProfileId = profile.id);
    try {
      await state.audio.playUrl(audioUrl, headers: headers);
    } catch (_) {
      // Ignored
    } finally {
      if (mounted) setState(() => _previewingProfileId = null);
    }
  }

  Future<void> _confirmDeleteProfile(VoiceProfile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Obriši glasovni profil', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
          ],
        ),
        content: Text(
          'Jeste li sigurni da želite trajno obrisati profil "${profile.name}"?\n\nOva radnja se ne može poništiti.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Obriši'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final state = context.read<AppState>();
      try {
        await state.deleteProfile(profile.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Glasovni profil "${profile.name}" je uspješno obrisan.'),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Greška pri brisanju profila: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Profiles & Clone'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Section 1: Record New Voice
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isRecording ? AppTheme.primaryNeon : AppTheme.border,
                width: _isRecording ? 1.5 : 1,
              ),
              boxShadow: _isRecording
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryNeon.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                const Text(
                  'CLONE A NEW VOICE',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Record 5–15 seconds of clean, clear speech into the phone mic.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Record Button & Timer
                GestureDetector(
                  onTap: _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 88,
                    height: 88,
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
                      boxShadow: [
                        BoxShadow(
                          color: _isRecording
                              ? AppTheme.primaryNeon.withValues(alpha: 0.5)
                              : Colors.black.withValues(alpha: 0.2),
                          blurRadius: _isRecording ? 24 : 8,
                          spreadRadius: _isRecording ? 4 : 0,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 40,
                      color: _isRecording ? Colors.white : AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  _isRecording
                      ? 'Recording... 00:${_recordSeconds.toString().padLeft(2, '0')}'
                      : (_recordedFilePath != null ? 'Recording Ready (Tap to re-record)' : 'Tap mic to record'),
                  style: TextStyle(
                    color: _isRecording ? AppTheme.primaryNeon : AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: _isRecording ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider(color: AppTheme.border)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('OR', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    ),
                    Expanded(child: Divider(color: AppTheme.border)),
                  ],
                ),
                const SizedBox(height: 14),

                // File Picker Alternative
                OutlinedButton.icon(
                  onPressed: _isRecording ? null : _pickAudioFile,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Choose Audio File (.wav, .mp3)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentCyan,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),

                if (_recordedFilePath != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, size: 16, color: AppTheme.accentGreen),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Audio sample captured and verified',
                            style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accentGreen, size: 22),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Play sample',
                          onPressed: () => state.audio.playFile(File(_recordedFilePath!)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 18),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Discard sample',
                          onPressed: () => setState(() => _recordedFilePath = null),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Voice Profile Name',
                      hintText: 'e.g. My Custom Voice',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20, color: AppTheme.textMuted),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              SizedBox(width: 12),
                              Text('Saving Voice Profile...'),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Create Voice Profile'),
                            ],
                          ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Section 2: Existing Profiles List
          Text(
            'SAVED PROFILES (${state.profiles.length})',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          if (state.profiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Center(
                child: Text(
                  'No voice profiles found on server.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.profiles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final profile = state.profiles[index];
                final isSelected = state.selectedProfile?.id == profile.id;
                final isPreviewing = _previewingProfileId == profile.id;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.surfaceHighlight : AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: (isSelected ? AppTheme.primary : AppTheme.accentCyan).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'V',
                            style: TextStyle(
                              color: isSelected ? AppTheme.primary : AppTheme.accentCyan,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: TextStyle(
                                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            Text(
                              profile.kind == 'clone' ? 'Cloned reference voice' : 'Designed voice',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isPreviewing ? Icons.stop_rounded : Icons.volume_up_rounded,
                          color: AppTheme.accentCyan,
                          size: 22,
                        ),
                        tooltip: 'Preview reference audio',
                        onPressed: () => _playProfileSample(profile),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 22, color: Colors.redAccent),
                        tooltip: 'Obriši profil',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _confirmDeleteProfile(profile),
                      ),
                      const SizedBox(width: 4),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: () => state.selectProfile(profile),
                          child: const Text('Select', style: TextStyle(fontSize: 12.5)),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
