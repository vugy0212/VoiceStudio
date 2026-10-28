import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../state/app_state.dart';
import '../models/voice_profile.dart';
import '../services/api_client.dart';
import '../services/recorder_service.dart';

class VoiceCloneScreen extends StatefulWidget {
  final int initialTabIndex;

  const VoiceCloneScreen({super.key, this.initialTabIndex = 0});

  @override
  State<VoiceCloneScreen> createState() => _VoiceCloneScreenState();
}

class _VoiceCloneScreenState extends State<VoiceCloneScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // --- Tab 1: Clone + AI Denoise ---
  final TextEditingController _nameController = TextEditingController();
  bool _isRecording = false;
  int _recordSeconds = 0;
  double _currentNormalizedLevel = 0.0;
  Timer? _recordTimer;
  Timer? _ampTimer;
  String? _recordedFilePath;
  bool _autoCleanAfterRecord = true;
  bool _isCleaningAudio = false;
  bool _isSampleCleaned = false;
  bool _isSaving = false;
  String? _previewingProfileId;
  RecorderService? _recorder;

  // --- Tab 2: Voice Design from Description ---
  final TextEditingController _designNameController = TextEditingController();
  final TextEditingController _designDescController = TextEditingController();
  Map<String, dynamic> _designedAttrs = {
    'Gender': 'Auto',
    'Age': 'Auto',
    'Pitch': 'Auto',
    'Accent': 'Auto',
    'Whisper': 'Auto',
  };
  String _designedInstruct = '';
  bool _isAnalyzingDesc = false;
  bool _isSavingDesign = false;

  // --- Tab 3: Archetypes Catalog ---
  final TextEditingController _archSearchController = TextEditingController();
  String _archGenderFilter = 'All';
  List<ArchetypeItem> _archetypes = [];
  bool _isLoadingArchetypes = false;
  String? _previewingArchetypeId;
  String? _activatingArchetypeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() {
      if (_tabController.index == 2 && _archetypes.isEmpty && !_isLoadingArchetypes) {
        _loadArchetypes();
      }
    });
    if (widget.initialTabIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadArchetypes());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recorder = context.read<AppState>().recorder;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _designNameController.dispose();
    _designDescController.dispose();
    _archSearchController.dispose();
    _recordTimer?.cancel();
    _ampTimer?.cancel();
    if (_isRecording && _recorder != null) {
      _recorder!.stopRecording();
    }
    super.dispose();
  }

  // ==================== TAB 1: CLONE & DENOISE ====================

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
        _recordedFilePath = path;
        _isSampleCleaned = false;
      });
      if (path != null) {
        if (_autoCleanAfterRecord && state.isConnected) {
          await _cleanSampleAudio();
        } else {
          await state.audio.playFile(File(path));
        }
      }
    } else {
      try {
        await state.recorder.startRecording();
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
          _currentNormalizedLevel = 0.0;
          _recordedFilePath = null;
          _isSampleCleaned = false;
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
            if (mounted) {
              setState(() => _currentNormalizedLevel = norm);
            }
          } catch (_) {}
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() => _recordSeconds++);
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
            SnackBar(content: Text('Greška mikrofona: $e'), backgroundColor: AppTheme.primary),
          );
        }
      }
    }
  }

  Future<void> _cleanSampleAudio() async {
    if (_recordedFilePath == null || _isCleaningAudio) return;
    final state = context.read<AppState>();
    setState(() => _isCleaningAudio = true);
    try {
      final cleanedFile = await state.api.cleanAudio(File(_recordedFilePath!));
      if (!mounted) return;
      setState(() {
        _recordedFilePath = cleanedFile.path;
        _isSampleCleaned = true;
      });
      await state.audio.playFile(cleanedFile);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Pozadinski šum uklonjen (AI Demucs izolacija glasa)!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Čišćenje šuma nije uspjelo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isCleaningAudio = false);
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
        _isSampleCleaned = false;
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
          content: Text('Unesite naziv za novi glasovni profil.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    if (_recordedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Najprije snimite glas ili odaberite audio datoteku.'),
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
            content: Text('Glasovni profil "${profile.name}" uspješno kreiran!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Greška pri spremanju profila: $e'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==================== TAB 2: VOICE DESIGN ====================

  Future<void> _analyzeVoiceDescription(String description) async {
    if (description.trim().isEmpty) return;
    final state = context.read<AppState>();
    setState(() => _isAnalyzingDesc = true);
    try {
      final res = await state.api.describeVoice(description);
      if (!mounted) return;
      final attrs = res['attrs'];
      final instruct = res['instruct']?.toString() ?? '';
      setState(() {
        if (attrs is Map) {
          _designedAttrs = Map<String, dynamic>.from(attrs);
        }
        _designedInstruct = instruct;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzingDesc = false);
    }
  }

  Future<void> _saveDesignedVoice() async {
    final name = _designNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unesite naziv za dizajnirani glasovni profil.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    setState(() => _isSavingDesign = true);
    final state = context.read<AppState>();
    try {
      // If user typed description without clicking analyze first, parse it now
      if (_designedInstruct.isEmpty && _designDescController.text.trim().isNotEmpty) {
        await _analyzeVoiceDescription(_designDescController.text);
      }

      final profile = await state.createDesignedProfile(
        name: name,
        vdStates: _designedAttrs,
        instruct: _designedInstruct,
        language: state.language,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dizajnirani glas "${profile.name}" kreiran i odabran!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDesign = false);
    }
  }

  // ==================== TAB 3: ARCHETYPES CATALOG ====================

  Future<void> _loadArchetypes() async {
    final state = context.read<AppState>();
    setState(() => _isLoadingArchetypes = true);
    try {
      final list = await state.api.getArchetypes(
        query: _archSearchController.text,
        gender: _archGenderFilter,
      );
      if (mounted) {
        setState(() => _archetypes = list);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingArchetypes = false);
    }
  }

  Future<void> _previewArchetype(ArchetypeItem item) async {
    final state = context.read<AppState>();
    if (_previewingArchetypeId == item.id) {
      await state.audio.stop();
      setState(() => _previewingArchetypeId = null);
      return;
    }
    setState(() => _previewingArchetypeId = item.id);
    try {
      final url = state.api.getArchetypePreviewUrl(item.id);
      await state.audio.playUrl(url, headers: state.api.getAuthHeaders());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uzorak nije dostupan: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _previewingArchetypeId = null);
    }
  }

  Future<void> _activateArchetype(ArchetypeItem item) async {
    final state = context.read<AppState>();
    setState(() => _activatingArchetypeId = item.id);
    try {
      final profile = await state.useArchetype(item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Arhetip "${profile.name}" dodan u vaše glasove!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _activatingArchetypeId = null);
    }
  }

  // ==================== SHARED PROFILE ACTIONS ====================

  Future<void> _playProfileSample(VoiceProfile profile) async {
    final state = context.read<AppState>();
    final audioUrl = state.api.getProfileAudioUrl(profile.id);
    final headers = state.api.getAuthHeaders();

    setState(() => _previewingProfileId = profile.id);
    try {
      await state.audio.playUrl(audioUrl, headers: headers);
    } catch (_) {
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
        title: const Text('Studio za glasove'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentCyan,
          labelColor: AppTheme.accentCyan,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.mic_rounded, size: 18), text: 'Kloniraj'),
            Tab(icon: Icon(Icons.auto_fix_high_rounded, size: 18), text: 'Dizajniraj'),
            Tab(icon: Icon(Icons.theater_comedy_rounded, size: 18), text: 'Arhetipovi'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCloneTab(state),
          _buildDesignTab(state),
          _buildArchetypesTab(state),
        ],
      ),
    );
  }

  Widget _buildCloneTab(AppState state) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
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
                'KLONIRAJ GLAS (WAV 24kHz + AI DENOISE)',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Snimite 5–15 sekundi govora. Ugrađeni AI Denoise automatski uklanja šum prostorije.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 22),

              GestureDetector(
                onTap: _toggleRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 88 + (_isRecording ? (_currentNormalizedLevel * 14) : 0),
                  height: 88 + (_isRecording ? (_currentNormalizedLevel * 14) : 0),
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
                    size: 40,
                    color: _isRecording ? Colors.white : AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                _isRecording
                    ? 'Snimanje... 00:${_recordSeconds.toString().padLeft(2, '0')} / 00:20'
                    : (_recordedFilePath != null
                        ? 'Snimka spremna (Dodirnite za ponovno snimanje)'
                        : 'Dodirnite mikrofon za početak snimanja'),
                style: TextStyle(
                  color: _isRecording ? AppTheme.primaryNeon : AppTheme.textMuted,
                  fontSize: 13,
                  fontWeight: _isRecording ? FontWeight.w700 : FontWeight.w500,
                ),
              ),

              if (_isRecording) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 26,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(18, (i) {
                      final threshold = (i + 1) / 18.0;
                      final active = _currentNormalizedLevel >= threshold * 0.85;
                      final barHeight = 8.0 + math.sin((i / 18.0) * math.pi) * 16.0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: 4,
                        height: active ? barHeight : 6,
                        decoration: BoxDecoration(
                          color: active
                              ? (i > 14 ? Colors.redAccent : AppTheme.accentCyan)
                              : AppTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Automatski očisti šum nakon snimanja (AI Denoise)',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Koristi Demucs izolaciju vokala na računalu za čistiji klon.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
                value: _autoCleanAfterRecord,
                activeThumbColor: AppTheme.accentCyan,
                onChanged: (v) => setState(() => _autoCleanAfterRecord = v),
              ),

              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isRecording ? null : _pickAudioFile,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Odaberi audio datoteku (.wav, .mp3, .m4a)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentCyan,
                  side: const BorderSide(color: AppTheme.border),
                ),
              ),

              if (_recordedFilePath != null || _isCleaningAudio) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      if (_isCleaningAudio)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                        )
                      else
                        Icon(
                          _isSampleCleaned ? Icons.auto_fix_high_rounded : Icons.check_circle,
                          size: 17,
                          color: AppTheme.accentGreen,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isCleaningAudio
                              ? 'AI Denoise čisti šum i izolira vokal...'
                              : (_isSampleCleaned
                                  ? 'Uzorak očišćen od šuma (AI Vocal Isolation)'
                                  : 'Audio uzorak spreman za kloniranje'),
                          style: const TextStyle(
                            color: AppTheme.accentGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_isCleaningAudio && !_isSampleCleaned)
                        TextButton.icon(
                          onPressed: _cleanSampleAudio,
                          icon: const Icon(Icons.cleaning_services_rounded, size: 14),
                          label: const Text('Očisti šum', style: TextStyle(fontSize: 11.5)),
                        ),
                      if (!_isCleaningAudio && _recordedFilePath != null)
                        IconButton(
                          icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accentGreen, size: 22),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Poslušaj uzorak',
                          onPressed: () => state.audio.playFile(File(_recordedFilePath!)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Naziv glasovnog profila',
                    hintText: 'npr. Moj glas',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20, color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: (_isSaving || _isCleaningAudio) ? null : _saveProfile,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_isSaving ? 'Spremanje profila...' : 'Kreiraj klonirani profil'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        _buildSavedProfilesList(state),
      ],
    );
  }

  Widget _buildDesignTab(AppState state) {
    const presets = [
      {'label': '🎬 Filmski narator', 'desc': 'deep male voice, middle-aged, calm, studio narrator'},
      {'label': '✨ Topli ženski glas', 'desc': 'young adult female, warm, moderate pitch, clear'},
      {'label': '🧙‍♂️ Stariji mudrac', 'desc': 'elderly male, low pitch, british accent'},
      {'label': '🌙 Tihi šapat', 'desc': 'female, whisper, soft, young adult'},
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'DIZAJNIRAJ GLAS IZ OPISA (BEZ SNIMKE)',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Opišite kakav glas želite (spol, dob, visinu tona, naglasak ili šapat) i VoiceStudio će sintetizirati jedinstveni profil.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((p) {
                  return ActionChip(
                    label: Text(p['label']!, style: const TextStyle(fontSize: 11.5, color: AppTheme.textPrimary)),
                    backgroundColor: AppTheme.surfaceElevated,
                    side: const BorderSide(color: AppTheme.border),
                    onPressed: () {
                      _designDescController.text = p['desc']!;
                      _analyzeVoiceDescription(p['desc']!);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _designDescController,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
                decoration: InputDecoration(
                  labelText: 'Opis glasa (engleski ili ključne riječi)',
                  hintText: 'e.g. young female, high pitch, british accent, whisper...',
                  suffixIcon: IconButton(
                    icon: _isAnalyzingDesc
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, color: AppTheme.accentCyan),
                    tooltip: 'Analiziraj opis',
                    onPressed: () => _analyzeVoiceDescription(_designDescController.text),
                  ),
                ),
                onSubmitted: _analyzeVoiceDescription,
              ),
              const SizedBox(height: 14),

              // Attribute Chips summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PREPOZNATI ATRIBUTI GLASA',
                      style: TextStyle(color: AppTheme.accentCyan, fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _designedAttrs.entries.map((e) {
                        final isSet = e.value != null && e.value.toString() != 'Auto';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSet
                                ? AppTheme.primary.withValues(alpha: 0.2)
                                : AppTheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSet ? AppTheme.primary : AppTheme.border,
                            ),
                          ),
                          child: Text(
                            '${e.key}: ${e.value}',
                            style: TextStyle(
                              color: isSet ? Colors.white : AppTheme.textMuted,
                              fontSize: 11,
                              fontWeight: isSet ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_designedInstruct.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Instruct: $_designedInstruct',
                        style: const TextStyle(color: AppTheme.accentGreen, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _designNameController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Naziv novog profila',
                  hintText: 'npr. Filmski Narator',
                  prefixIcon: Icon(Icons.record_voice_over_rounded, size: 20, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _isSavingDesign ? null : _saveDesignedVoice,
                icon: _isSavingDesign
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 20),
                label: Text(_isSavingDesign ? 'Kreiram dizajnirani glas...' : 'Kreiraj dizajnirani glas'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArchetypesTab(AppState state) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _archSearchController,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Pretraži arhetipove (npr. narrator, british, calm)...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.textMuted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixIcon: _archSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _archSearchController.clear();
                              _loadArchetypes();
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _loadArchetypes(),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _archGenderFilter,
                dropdownColor: AppTheme.surfaceElevated,
                style: const TextStyle(color: AppTheme.accentCyan, fontSize: 12.5, fontWeight: FontWeight.w700),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('Svi')),
                  DropdownMenuItem(value: 'female', child: Text('Ženski')),
                  DropdownMenuItem(value: 'male', child: Text('Muški')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _archGenderFilter = val);
                    _loadArchetypes();
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingArchetypes
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
              : _archetypes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.theater_comedy_outlined, size: 48, color: AppTheme.textMuted),
                          const SizedBox(height: 10),
                          const Text(
                            'Učitajte katalog gotovih arhetipova sa poslužitelja',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _loadArchetypes,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Dohvati katalog arhetipova'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _archetypes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final arch = _archetypes[index];
                        final isPreviewing = _previewingArchetypeId == arch.id;
                        final isActivating = _activatingArchetypeId == arch.id;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isPreviewing ? AppTheme.accentCyan : AppTheme.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  isPreviewing ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                                  color: AppTheme.accentCyan,
                                  size: 32,
                                ),
                                tooltip: 'Poslušaj uzorak arhetipa',
                                onPressed: () => _previewArchetype(arch),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      arch.name,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (arch.useCase.isNotEmpty) arch.useCase,
                                        if (arch.gender.isNotEmpty) arch.gender,
                                        if (arch.age.isNotEmpty) arch.age,
                                        if (arch.accent.isNotEmpty) arch.accent,
                                      ].join(' • '),
                                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: isActivating ? null : () => _activateArchetype(arch),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                icon: isActivating
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.add_rounded, size: 17),
                                label: Text(
                                  isActivating ? 'Dodajem...' : 'Koristi',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSavedProfilesList(AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SPREMLJENI PROFILI (${state.profiles.length})',
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
                'Nema pronađenih glasovnih profila na poslužitelju.',
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
                            profile.kind == 'clone' ? 'Klonirani referentni glas' : 'Dizajnirani glas',
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
                      tooltip: 'Poslušaj referentni uzorak',
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
                          'Aktivno',
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
                        child: const Text('Odaberi', style: TextStyle(fontSize: 12.5)),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
