class AppConstants {
  // Firebase Hub Configuration (Cloud Firestore & Auth)
  static const String firebaseProjectId = 'voicestudio-mobile-hub';
  static const String firebaseApiKey = 'AIzaSyC6kh1xub67idTbzx93SeroPYZmV_y1jiM';
  static const String adminOwnerEmail = 'vugy0212@gmail.com';

  // Default empty connection values (fetched dynamically from Firebase Hub after user approval!)
  static const String defaultServerUrl = '';
  static const String defaultLocalUrl = '';
  static const String defaultRemoteUrl = '';
  static const String defaultCfClientId = '';
  static const String defaultCfClientSecret = '';

  static const String prefServerUrl = 'vs_server_url';
  static const String prefLocalUrl = 'vs_local_url';
  static const String prefRemoteUrl = 'vs_remote_url';
  static const String prefConnectionMode = 'vs_conn_mode'; // 'auto', 'local', 'remote'
  static const String prefCfClientId = 'vs_cf_client_id';
  static const String prefCfClientSecret = 'vs_cf_client_secret';
  static const String prefSelectedVoiceId = 'vs_selected_voice_id';
  static const String prefSpeed = 'vs_speed';
  static const String prefLanguage = 'vs_language';
  static const String prefSteps = 'vs_steps';
  static const String prefGuidanceScale = 'vs_guidance_scale';
  static const String prefInstruct = 'vs_instruct';
  static const String prefSavedAudios = 'vs_saved_audios';
  static const String prefStreamingEnabled = 'vs_streaming_enabled';
  static const String prefCachedProfiles = 'vs_cached_profiles';
  static const String prefDraftText = 'vs_draft_text';
  static const String prefCurrentUserJson = 'vs_current_user_json';

  static const List<double> availableSpeeds = [0.8, 1.0, 1.25, 1.5, 2.0];
  static const List<String> availableLanguages = ['Auto', 'Croatian', 'English', 'Serbian', 'German', 'Italian', 'Spanish'];

  static const List<Map<String, String>> emotionPresets = [
    {'label': 'Normalno', 'prompt': ''},
    {'label': 'Šapat', 'prompt': 'whisper'},
    {'label': 'Duboki glas', 'prompt': 'low pitch'},
    {'label': 'Visoki glas', 'prompt': 'high pitch'},
    {'label': 'Mlađi glas', 'prompt': 'young adult'},
    {'label': 'Stariji glas', 'prompt': 'elderly'},
    {'label': 'Umjereno', 'prompt': 'moderate pitch'},
    {'label': 'Duboki šapat', 'prompt': 'whisper, low pitch'},
  ];
}
