import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/saved_audio.dart';

class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  String getServerUrl() {
    return _prefs.getString(AppConstants.prefServerUrl) ?? AppConstants.defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    await _prefs.setString(AppConstants.prefServerUrl, url.trim());
  }

  String getLocalUrl() {
    return _prefs.getString(AppConstants.prefLocalUrl) ?? AppConstants.defaultLocalUrl;
  }

  Future<void> setLocalUrl(String url) async {
    await _prefs.setString(AppConstants.prefLocalUrl, url.trim());
  }

  String getRemoteUrl() {
    return _prefs.getString(AppConstants.prefRemoteUrl) ?? AppConstants.defaultRemoteUrl;
  }

  Future<void> setRemoteUrl(String url) async {
    await _prefs.setString(AppConstants.prefRemoteUrl, url.trim());
  }

  String getConnectionMode() {
    return _prefs.getString(AppConstants.prefConnectionMode) ?? 'auto';
  }

  Future<void> setConnectionMode(String mode) async {
    await _prefs.setString(AppConstants.prefConnectionMode, mode);
  }

  bool isStreamingEnabled() {
    return _prefs.getBool(AppConstants.prefStreamingEnabled) ?? false;
  }

  Future<void> setStreamingEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.prefStreamingEnabled, enabled);
  }

  String getCfClientId() {
    final val = _prefs.getString(AppConstants.prefCfClientId);
    if (val != null && val.trim().isNotEmpty) return val.trim();
    return AppConstants.defaultCfClientId;
  }

  Future<void> setCfClientId(String id) async {
    await _prefs.setString(AppConstants.prefCfClientId, id.trim());
  }

  String getCfClientSecret() {
    final val = _prefs.getString(AppConstants.prefCfClientSecret);
    if (val != null && val.trim().isNotEmpty) return val.trim();
    return AppConstants.defaultCfClientSecret;
  }

  Future<void> setCfClientSecret(String secret) async {
    await _prefs.setString(AppConstants.prefCfClientSecret, secret.trim());
  }

  String? getSelectedVoiceId() {
    return _prefs.getString(AppConstants.prefSelectedVoiceId);
  }

  Future<void> setSelectedVoiceId(String? id) async {
    if (id == null) {
      await _prefs.remove(AppConstants.prefSelectedVoiceId);
    } else {
      await _prefs.setString(AppConstants.prefSelectedVoiceId, id);
    }
  }

  double getSpeed() {
    return _prefs.getDouble(AppConstants.prefSpeed) ?? 1.0;
  }

  Future<void> setSpeed(double speed) async {
    await _prefs.setDouble(AppConstants.prefSpeed, speed);
  }

  String getLanguage() {
    return _prefs.getString(AppConstants.prefLanguage) ?? 'Auto';
  }

  Future<void> setLanguage(String language) async {
    await _prefs.setString(AppConstants.prefLanguage, language);
  }

  int getSteps() {
    return _prefs.getInt(AppConstants.prefSteps) ?? 16;
  }

  Future<void> setSteps(int steps) async {
    await _prefs.setInt(AppConstants.prefSteps, steps);
  }

  double getGuidanceScale() {
    return _prefs.getDouble(AppConstants.prefGuidanceScale) ?? 2.0;
  }

  Future<void> setGuidanceScale(double scale) async {
    await _prefs.setDouble(AppConstants.prefGuidanceScale, scale);
  }

  String getInstruct() {
    return _prefs.getString(AppConstants.prefInstruct) ?? '';
  }

  Future<void> setInstruct(String instruct) async {
    await _prefs.setString(AppConstants.prefInstruct, instruct.trim());
  }

  List<SavedAudio> getSavedAudios() {
    final raw = _prefs.getString(AppConstants.prefSavedAudios);
    if (raw == null || raw.isEmpty) return [];
    return SavedAudio.decodeList(raw);
  }

  Future<void> saveAudio(SavedAudio audio) async {
    final list = getSavedAudios();
    // Remove if existing with same id, then prepend
    list.removeWhere((item) => item.id == audio.id);
    list.insert(0, audio);
    await _prefs.setString(AppConstants.prefSavedAudios, SavedAudio.encodeList(list));
  }

  Future<void> deleteSavedAudio(String id) async {
    final list = getSavedAudios();
    list.removeWhere((item) => item.id == id);
    await _prefs.setString(AppConstants.prefSavedAudios, SavedAudio.encodeList(list));
  }

  Future<void> toggleFavoriteAudio(String id) async {
    final list = getSavedAudios();
    final index = list.indexWhere((item) => item.id == id);
    if (index != -1) {
      list[index] = list[index].copyWith(isFavorite: !list[index].isFavorite);
      await _prefs.setString(AppConstants.prefSavedAudios, SavedAudio.encodeList(list));
    }
  }
}
