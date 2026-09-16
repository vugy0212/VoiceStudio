import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/voice_profile.dart';
import '../models/generation_history.dart';
import '../models/saved_audio.dart';
import '../services/storage_service.dart';
import '../services/api_client.dart';
import '../services/audio_service.dart';
import '../services/recorder_service.dart';

class AppState extends ChangeNotifier {
  final StorageService storage;
  final ApiClient api;
  final AudioService audio;
  final RecorderService recorder;

  AppState({
    required this.storage,
    required this.api,
    required this.audio,
    required this.recorder,
  });

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isCheckingConnection = false;
  bool get isCheckingConnection => _isCheckingConnection;

  List<VoiceProfile> _profiles = [];
  List<VoiceProfile> get profiles => _profiles;

  VoiceProfile? _selectedProfile;
  VoiceProfile? get selectedProfile => _selectedProfile;

  bool _isLoadingProfiles = false;
  bool get isLoadingProfiles => _isLoadingProfiles;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  double _generationElapsed = 0.0;
  double get generationElapsed => _generationElapsed;
  Timer? _timer;

  int _streamingChunkCount = 0;
  int get streamingChunkCount => _streamingChunkCount;

  GenerateResult? _lastGeneration;
  GenerateResult? get lastGeneration => _lastGeneration;

  List<GenerationHistory> _history = [];
  List<GenerationHistory> get history => _history;

  bool _isLoadingHistory = false;
  bool get isLoadingHistory => _isLoadingHistory;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _localServerUrl = '';
  String get localServerUrl => _localServerUrl;

  String _remoteServerUrl = '';
  String get remoteServerUrl => _remoteServerUrl;

  String _connectionMode = 'auto';
  String get connectionMode => _connectionMode;

  String get activeBaseUrl => api.baseUrl;
  bool get isUsingLocalUrl => api.isUsingLocalUrl;

  String _cfClientId = '';
  String get cfClientId => _cfClientId;

  String _cfClientSecret = '';
  String get cfClientSecret => _cfClientSecret;

  bool _streamingEnabled = false;
  bool get streamingEnabled => _streamingEnabled;

  double _speed = 1.0;
  double get speed => _speed;

  String _language = 'Auto';
  String get language => _language;

  String _instruct = '';
  String get instruct => _instruct;

  int _steps = 16;
  int get steps => _steps;

  double _guidanceScale = 2.0;
  double get guidanceScale => _guidanceScale;

  List<SavedAudio> _savedAudios = [];
  List<SavedAudio> get savedAudios => _savedAudios;

  Future<void> init() async {
    _localServerUrl = storage.getLocalUrl();
    _remoteServerUrl = storage.getRemoteUrl();
    _connectionMode = storage.getConnectionMode();
    _cfClientId = storage.getCfClientId();
    _cfClientSecret = storage.getCfClientSecret();
    _streamingEnabled = storage.isStreamingEnabled();

    _speed = storage.getSpeed();
    _language = storage.getLanguage();
    _instruct = '';
    await storage.setInstruct('');
    _steps = storage.getSteps();
    _guidanceScale = storage.getGuidanceScale();
    _savedAudios = storage.getSavedAudios();

    _isInitialized = true;
    notifyListeners();

    await testConnectionAndRefresh();
  }


  Future<void> testConnectionAndRefresh() async {
    _isCheckingConnection = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _isConnected = await api.checkConnection();
      if (_isConnected) {
        await refreshProfiles();
        await refreshHistory();
      }
    } catch (e) {
      _isConnected = false;
      _errorMessage = e.toString();
    } finally {
      _isCheckingConnection = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> testDetailedEndpoints() async {
    _isCheckingConnection = true;
    notifyListeners();
    try {
      final res = await api.testEndpoints();
      _isConnected = (res['localOk'] == true || res['remoteOk'] == true);
      if (_isConnected) {
        unawaited(refreshProfiles());
        unawaited(refreshHistory());
      }
      return res;
    } finally {
      _isCheckingConnection = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfiles() async {
    _isLoadingProfiles = true;
    notifyListeners();

    try {
      _profiles = await api.getProfiles();
      final savedId = storage.getSelectedVoiceId();
      if (savedId != null && _profiles.any((p) => p.id == savedId)) {
        _selectedProfile = _profiles.firstWhere((p) => p.id == savedId);
      } else if (_profiles.isNotEmpty && _selectedProfile == null) {
        _selectedProfile = _profiles.first;
      }
    } catch (e) {
      _errorMessage = 'Greška učitavanja profila: $e';
    } finally {
      _isLoadingProfiles = false;
      notifyListeners();
    }
  }

  void selectProfile(VoiceProfile? profile) {
    _selectedProfile = profile;
    storage.setSelectedVoiceId(profile?.id);
    notifyListeners();
  }

  Future<void> setSpeed(double newSpeed) async {
    _speed = newSpeed;
    await storage.setSpeed(newSpeed);
    await audio.setPlaybackSpeed(newSpeed);
    notifyListeners();
  }

  Future<void> setLanguage(String newLang) async {
    _language = newLang;
    await storage.setLanguage(newLang);
    notifyListeners();
  }

  Future<void> setInstruct(String newInstruct) async {
    _instruct = newInstruct;
    await storage.setInstruct(newInstruct);
    notifyListeners();
  }

  Future<void> setSteps(int newSteps) async {
    _steps = newSteps;
    await storage.setSteps(newSteps);
    notifyListeners();
  }

  Future<void> setGuidanceScale(double newScale) async {
    _guidanceScale = newScale;
    await storage.setGuidanceScale(newScale);
    notifyListeners();
  }

  Future<void> setStreamingEnabled(bool enabled) async {
    _streamingEnabled = enabled;
    await storage.setStreamingEnabled(enabled);
    notifyListeners();
  }

  Future<void> updateConnectionSettings({
    required String newLocalUrl,
    required String newRemoteUrl,
    required String newConnectionMode,
    required String newCfClientId,
    required String newCfClientSecret,
    required bool newStreamingEnabled,
  }) async {
    _localServerUrl = newLocalUrl;
    _remoteServerUrl = newRemoteUrl;
    _connectionMode = newConnectionMode;
    _cfClientId = newCfClientId;
    _cfClientSecret = newCfClientSecret;
    _streamingEnabled = newStreamingEnabled;

    await storage.setLocalUrl(newLocalUrl);
    await storage.setRemoteUrl(newRemoteUrl);
    await storage.setConnectionMode(newConnectionMode);
    await storage.setCfClientId(newCfClientId);
    await storage.setCfClientSecret(newCfClientSecret);
    await storage.setStreamingEnabled(newStreamingEnabled);
    api.resetActiveBaseUrl();

    notifyListeners();
    await testConnectionAndRefresh();
  }

  Future<void> generateSpeech(String text) async {
    if (text.trim().isEmpty) return;

    _isGenerating = true;
    _generationElapsed = 0.0;
    _streamingChunkCount = 0;
    _errorMessage = null;
    notifyListeners();

    final startTime = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      _generationElapsed = (DateTime.now().difference(startTime).inMilliseconds / 1000.0);
      notifyListeners();
    });

    try {
      GenerateResult result;
      if (_streamingEnabled) {
        await audio.prepareStreaming();
        result = await api.generateSpeechStream(
          text: text,
          profileId: _selectedProfile?.id,
          speed: _speed,
          language: _language,
          instruct: _instruct,
          steps: _steps,
          guidanceScale: _guidanceScale,
          onChunkReady: (seq, chunkWav, totalChunks) {
            _streamingChunkCount = seq + 1;
            audio.addStreamChunk(chunkWav);
            notifyListeners();
          },
        );
        await audio.finalizeStreaming(result.audioFile);
      } else {
        result = await api.generateSpeech(
          text: text,
          profileId: _selectedProfile?.id,
          speed: _speed,
          language: _language,
          instruct: _instruct,
          steps: _steps,
          guidanceScale: _guidanceScale,
        );
        await audio.playFile(result.audioFile);
      }

      _lastGeneration = result;
      unawaited(refreshHistory());
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _timer?.cancel();
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> refreshHistory() async {
    _isLoadingHistory = true;
    notifyListeners();

    try {
      _history = await api.getHistory();
    } catch (_) {
      // Ignored non-critical history errors
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<VoiceProfile> createProfile({
    required String name,
    required String audioPath,
  }) async {
    try {
      final profile = await api.createProfile(name: name, audioPath: audioPath);
      await refreshProfiles();
      selectProfile(profile);
      return profile;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteProfile(String profileId) async {
    try {
      await api.deleteProfile(profileId);
      if (_selectedProfile?.id == profileId) {
        _selectedProfile = null;
        storage.setSelectedVoiceId(null);
      }
      await refreshProfiles();
    } catch (e) {
      _errorMessage = 'Greška brisanja profila: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Save generated take to persistent offline library on phone
  Future<SavedAudio> saveToLibrary({
    required File file,
    required String text,
    required String profileName,
    double? duration,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final libDir = Directory('${docsDir.path}/VoiceStudio_Library');
    if (!await libDir.exists()) {
      await libDir.create(recursive: true);
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final targetPath = '${libDir.path}/take_$id.wav';
    final copiedFile = await file.copy(targetPath);

    final title = text.trim().length > 30 ? '${text.trim().substring(0, 30)}...' : text.trim();

    final item = SavedAudio(
      id: id,
      title: title.isEmpty ? 'Audio Zapis $id' : title,
      filePath: copiedFile.path,
      duration: duration ?? 0.0,
      createdAt: DateTime.now(),
      profileName: profileName,
      text: text,
      isFavorite: false,
    );

    await storage.saveAudio(item);
    _savedAudios = storage.getSavedAudios();
    notifyListeners();
    return item;
  }

  Future<void> deleteSavedAudio(String id) async {
    final item = _savedAudios.firstWhere((a) => a.id == id, orElse: () => SavedAudio(
      id: '',
      title: '',
      filePath: '',
      duration: 0,
      createdAt: DateTime.now(),
      profileName: '',
      text: '',
    ));

    if (item.filePath.isNotEmpty) {
      final f = File(item.filePath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    await storage.deleteSavedAudio(id);
    _savedAudios = storage.getSavedAudios();
    notifyListeners();
  }

  Future<void> toggleFavoriteAudio(String id) async {
    await storage.toggleFavoriteAudio(id);
    _savedAudios = storage.getSavedAudios();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
