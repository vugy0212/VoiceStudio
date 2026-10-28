import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_user.dart';
import '../models/voice_profile.dart';
import '../models/generation_history.dart';
import '../models/saved_audio.dart';
import '../services/storage_service.dart';
import '../services/api_client.dart';
import '../services/audio_service.dart';
import '../services/recorder_service.dart';
import '../services/firebase_hub_service.dart';
import '../utils/wav_utils.dart';

class AppState extends ChangeNotifier {
  final StorageService storage;
  final ApiClient api;
  final AudioService audio;
  final RecorderService recorder;
  final FirebaseHubService hub = FirebaseHubService();

  AppState({
    required this.storage,
    required this.api,
    required this.audio,
    required this.recorder,
  });

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isApprovedUser => _currentUser != null && _currentUser!.canUseApp;
  bool get isAdmin => _currentUser?.isAdmin == true;
  bool get isPremium => _currentUser?.isPremium == true;

  List<String> _allowedVoiceIds = List<String>.from(HubConnectionConfig.defaultAllowedVoiceIds);
  List<String> get allowedVoiceIds => _allowedVoiceIds;
  final Set<String> _myCreatedVoiceIds = {};

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String _backendStatus = 'OFFLINE'; // 'RUNNING', 'SLEEPING', 'STARTING', 'DIRECT', 'OFFLINE'
  String get backendStatus => _backendStatus;
  bool get isBackendSleeping => _backendStatus == 'SLEEPING';

  int _idleSecondsRemaining = 0;
  int get idleSecondsRemaining => _idleSecondsRemaining;

  int _queueLength = 0;
  int get queueLength => _queueLength;

  int _activeGpuJobs = 0;
  int get activeGpuJobs => _activeGpuJobs;

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

  CancelToken? _activeCancelToken;

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

  String _draftText = '';
  String get draftText => _draftText;

  List<SavedAudio> _savedAudios = [];
  List<SavedAudio> get savedAudios => _savedAudios;

  static const List<String> _defaultAllowedKeywords = [
    'pantić',
    'pantic',
    'šojić',
    'sojic',
    'dijete',
    'bata s',
  ];

  List<VoiceProfile> _filterProfilesForCurrentUser(List<VoiceProfile> all) {
    if (isAdmin || isPremium) return all;
    return all.where((p) {
      if (_allowedVoiceIds.contains(p.id)) return true;
      if (_myCreatedVoiceIds.contains(p.id)) return true;
      final lower = p.name.toLowerCase();
      return _defaultAllowedKeywords.any((kw) => lower.contains(kw));
    }).toList();
  }

  Future<void> init() async {
    _currentUser = storage.getCurrentUser();
    _localServerUrl = storage.getLocalUrl();
    _remoteServerUrl = storage.getRemoteUrl();
    _connectionMode = storage.getConnectionMode();
    _cfClientId = storage.getCfClientId();
    _cfClientSecret = storage.getCfClientSecret();
    _streamingEnabled = storage.isStreamingEnabled();

    _speed = storage.getSpeed();
    _language = storage.getLanguage();
    _instruct = storage.getInstruct();
    _steps = storage.getSteps();
    _guidanceScale = storage.getGuidanceScale();
    _draftText = storage.getDraftText();
    _savedAudios = storage.getSavedAudios();

    final cached = _filterProfilesForCurrentUser(storage.getCachedProfiles());
    if (cached.isNotEmpty) {
      _profiles = cached;
      final savedId = storage.getSelectedVoiceId();
      if (savedId != null && _profiles.any((p) => p.id == savedId)) {
        _selectedProfile = _profiles.firstWhere((p) => p.id == savedId);
      } else {
        _selectedProfile = _profiles.first;
      }
    }

    _isInitialized = true;
    notifyListeners();

    unawaited(WavUtils.cleanOldTempFiles());

    if (_currentUser != null) {
      await refreshUserAndSyncConfig();
    }
  }

  Future<void> refreshUserAndSyncConfig() async {
    if (_currentUser == null) return;
    try {
      final freshUser = await hub.refreshUserProfile(_currentUser!.uid);
      if (freshUser != null) {
        _currentUser = freshUser;
        await storage.setCurrentUser(freshUser);
      }
      if (_currentUser != null && _currentUser!.canUseApp) {
        final cfg = await hub.fetchConnectionConfig();
        await _applyHubConnectionConfig(cfg);
        await testConnectionAndRefresh();
      } else {
        await storage.clearSensitiveSessionData();
        if (_currentUser != null) {
          await storage.setCurrentUser(_currentUser);
        }
        _isConnected = false;
      }
    } catch (_) {
      if (_currentUser != null && _currentUser!.canUseApp) {
        await testConnectionAndRefresh();
      }
    }
    notifyListeners();
  }

  Future<void> _applyHubConnectionConfig(HubConnectionConfig cfg) async {
    _allowedVoiceIds = List<String>.from(cfg.allowedVoiceIds);
    if (cfg.remoteUrl.isNotEmpty) {
      _remoteServerUrl = cfg.remoteUrl;
      await storage.setRemoteUrl(cfg.remoteUrl);
    }
    if (cfg.localUrl.isNotEmpty && (_localServerUrl.isEmpty || !isAdmin)) {
      _localServerUrl = cfg.localUrl;
      await storage.setLocalUrl(cfg.localUrl);
    }
    if (cfg.cfClientId.isNotEmpty) {
      _cfClientId = cfg.cfClientId;
      await storage.setCfClientId(cfg.cfClientId);
    }
    if (cfg.cfClientSecret.isNotEmpty) {
      _cfClientSecret = cfg.cfClientSecret;
      await storage.setCfClientSecret(cfg.cfClientSecret);
    }
    api.resetActiveBaseUrl();
  }

  Future<AppUser> login({required String email, required String password}) async {
    final user = await hub.loginWithEmailPassword(email, password);
    _currentUser = user;
    _profiles = [];
    _selectedProfile = null;
    await storage.setCurrentUser(user);
    if (user.canUseApp) {
      final cfg = await hub.fetchConnectionConfig();
      await _applyHubConnectionConfig(cfg);
      unawaited(testConnectionAndRefresh());
    }
    notifyListeners();
    return user;
  }

  Future<AppUser> register({
    required String displayName,
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    final user = await hub.registerUser(
      displayName: displayName,
      email: email,
      password: password,
      inviteCode: inviteCode,
    );
    _currentUser = user;
    _profiles = [];
    _selectedProfile = null;
    await storage.setCurrentUser(user);
    if (user.canUseApp) {
      final cfg = await hub.fetchConnectionConfig();
      await _applyHubConnectionConfig(cfg);
      unawaited(testConnectionAndRefresh());
    }
    notifyListeners();
    return user;
  }

  Future<AppUser> redeemInviteCode({
    required String inviteCode,
    required String displayName,
  }) async {
    final user = await hub.redeemInviteCodeLogin(
      inviteCode: inviteCode,
      displayName: displayName,
    );
    _currentUser = user;
    _profiles = [];
    _selectedProfile = null;
    await storage.setCurrentUser(user);
    final cfg = await hub.fetchConnectionConfig();
    await _applyHubConnectionConfig(cfg);
    unawaited(testConnectionAndRefresh());
    notifyListeners();
    return user;
  }

  Future<void> logout() async {
    await audio.stop();
    _currentUser = null;
    _profiles = [];
    _selectedProfile = null;
    _myCreatedVoiceIds.clear();
    _isConnected = false;
    _backendStatus = 'OFFLINE';
    _localServerUrl = '';
    _remoteServerUrl = '';
    _cfClientId = '';
    _cfClientSecret = '';
    await storage.clearSensitiveSessionData();
    api.resetActiveBaseUrl();
    notifyListeners();
  }

  Future<void> recordQuotaUsage() async {
    if (_currentUser == null) return;
    final updated = await hub.incrementUserUsage(_currentUser!);
    _currentUser = updated;
    await storage.setCurrentUser(updated);
    notifyListeners();
  }

  Future<void> testConnectionAndRefresh({bool forceWake = false}) async {
    if (!isApprovedUser) return;
    _isCheckingConnection = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final info = await api.checkGatewayConnection();
      _isConnected = info.reachable;
      _backendStatus = info.backendStatus;
      _idleSecondsRemaining = info.idleSecondsRemaining;
      _queueLength = info.queueLength;
      _activeGpuJobs = info.activeGpuJobs;

      if (_isConnected) {
        if (!isBackendSleeping || _profiles.isEmpty || forceWake) {
          await refreshProfiles();
          await refreshHistory();
          _backendStatus = 'RUNNING';
        }
      }
    } catch (e) {
      _isConnected = false;
      _backendStatus = 'OFFLINE';
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isCheckingConnection = false;
      notifyListeners();
    }
  }

  Future<bool> wakeEngine() async {
    _isCheckingConnection = true;
    _backendStatus = 'STARTING';
    notifyListeners();
    try {
      final ok = await api.wakeGateway();
      await testConnectionAndRefresh(forceWake: true);
      return ok;
    } finally {
      _isCheckingConnection = false;
      notifyListeners();
    }
  }

  Future<bool> sleepEngine() async {
    if (!isAdmin) return false;
    _isCheckingConnection = true;
    notifyListeners();
    try {
      final ok = await api.sleepGateway();
      if (ok) {
        _backendStatus = 'SLEEPING';
        _idleSecondsRemaining = 0;
      }
      return ok;
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
        final activeState = (res['isUsingLocal'] == true ? res['localState'] : res['remoteState'])?.toString() ?? 'RUNNING';
        _backendStatus = activeState;
        if (_backendStatus != 'SLEEPING' || _profiles.isEmpty) {
          unawaited(refreshProfiles());
          unawaited(refreshHistory());
        }
      } else {
        _backendStatus = 'OFFLINE';
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
      final freshProfiles = await api.getProfiles();
      final filtered = _filterProfilesForCurrentUser(freshProfiles);
      if (filtered.isNotEmpty) {
        _profiles = filtered;
        await storage.setCachedProfiles(filtered);
      }
      final savedId = storage.getSelectedVoiceId();
      if (savedId != null && _profiles.any((p) => p.id == savedId)) {
        _selectedProfile = _profiles.firstWhere((p) => p.id == savedId);
      } else if (_profiles.isNotEmpty) {
        _selectedProfile = _profiles.first;
      }
    } catch (e) {
      _errorMessage = 'Greška učitavanja profila: ${e.toString().replaceAll("Exception: ", "")}';
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

  Future<void> setDraftText(String text, {bool notify = false}) async {
    _draftText = text;
    await storage.setDraftText(text);
    if (notify) notifyListeners();
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
    bool syncToFirebaseHub = false,
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

    if (syncToFirebaseHub && isAdmin) {
      final currentCfg = await hub.fetchConnectionConfig();
      await hub.saveConnectionConfig(
        HubConnectionConfig(
          remoteUrl: newRemoteUrl,
          localUrl: newLocalUrl,
          cfClientId: newCfClientId,
          cfClientSecret: newCfClientSecret,
          autoApproveNewUsers: currentCfg.autoApproveNewUsers,
          defaultDailyQuota: currentCfg.defaultDailyQuota,
          adminEmail: currentCfg.adminEmail,
          allowedVoiceIds: currentCfg.allowedVoiceIds,
        ),
      );
    }

    notifyListeners();
    await testConnectionAndRefresh();
  }

  Future<void> cancelGeneration() async {
    _activeCancelToken?.cancel('Korisnik prekinuo generiranje');
    _activeCancelToken = null;
    _timer?.cancel();
    _isGenerating = false;
    await audio.stop();
    notifyListeners();
  }

  Future<void> generateSpeech(String text) async {
    if (text.trim().isEmpty) return;

    if (_currentUser != null && !_currentUser!.hasQuotaLeft) {
      _errorMessage =
          'Dosegnuli ste dnevni limit (${_currentUser!.dailyQuota} sinteza danas). Pokušajte sutra ili kontaktirajte administratora.';
      notifyListeners();
      return;
    }

    if (!isAdmin && text.trim().length > 4000) {
      _errorMessage = 'Maksimalna duljina teksta po zahtjevu je 4.000 znakova.';
      notifyListeners();
      return;
    }

    _activeCancelToken?.cancel();
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    _isGenerating = true;
    _generationElapsed = 0.0;
    _streamingChunkCount = 0;
    _errorMessage = null;
    if (_backendStatus == 'SLEEPING') {
      _backendStatus = 'STARTING';
    }
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
          cancelToken: cancelToken,
          onChunkReady: (seq, chunkWav, totalChunks) {
            _backendStatus = 'RUNNING';
            _streamingChunkCount = seq + 1;
            audio.addStreamChunk(chunkWav);
            notifyListeners();
          },
        );
        await audio.finalizeStreaming(result.audioFile, chunkFiles: result.chunkFiles);
      } else {
        result = await api.generateSpeech(
          text: text,
          profileId: _selectedProfile?.id,
          speed: _speed,
          language: _language,
          instruct: _instruct,
          steps: _steps,
          guidanceScale: _guidanceScale,
          cancelToken: cancelToken,
        );
        await audio.playFile(result.audioFile);
      }

      _backendStatus = 'RUNNING';
      _lastGeneration = result;
      unawaited(recordQuotaUsage());
      unawaited(refreshHistory());
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (!msg.contains('prekinuto')) {
        _errorMessage = msg;
      }
    } finally {
      _timer?.cancel();
      _isGenerating = false;
      _activeCancelToken = null;
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
      _myCreatedVoiceIds.add(profile.id);
      _backendStatus = 'RUNNING';
      await refreshProfiles();
      selectProfile(profile);
      return profile;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<VoiceProfile> createDesignedProfile({
    required String name,
    required Map<String, dynamic> vdStates,
    required String instruct,
    String language = 'Auto',
    String sampleScript = '',
  }) async {
    try {
      final profile = await api.createDesignedProfile(
        name: name,
        vdStates: vdStates,
        instruct: instruct,
        language: language,
        sampleScript: sampleScript,
      );
      _myCreatedVoiceIds.add(profile.id);
      _backendStatus = 'RUNNING';
      await refreshProfiles();
      selectProfile(profile);
      return profile;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<VoiceProfile> useArchetype(String archetypeId, {String? customName}) async {
    try {
      final profile = await api.useArchetype(archetypeId, customName: customName);
      _myCreatedVoiceIds.add(profile.id);
      _backendStatus = 'RUNNING';
      await refreshProfiles();
      selectProfile(profile);
      return profile;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteProfile(String profileId) async {
    try {
      await api.deleteProfile(profileId);
      _myCreatedVoiceIds.remove(profileId);
      if (_selectedProfile?.id == profileId) {
        _selectedProfile = null;
        storage.setSelectedVoiceId(null);
      }
      await refreshProfiles();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

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

    final title = text.trim().length > 35 ? '${text.trim().substring(0, 35)}...' : text.trim();

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

  Future<SavedAudio> saveHistoryItemToLibrary(GenerationHistory historyItem) async {
    final tempFile = await api.downloadAudioFile(historyItem.filename);
    return await saveToLibrary(
      file: tempFile,
      text: historyItem.text,
      profileName: historyItem.profileName ?? 'Klonirani glas',
      duration: historyItem.duration,
    );
  }

  Future<void> deleteSavedAudio(String id) async {
    final item = _savedAudios.firstWhere(
      (a) => a.id == id,
      orElse: () => SavedAudio(
        id: '',
        title: '',
        filePath: '',
        duration: 0,
        createdAt: DateTime.now(),
        profileName: '',
        text: '',
      ),
    );

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
