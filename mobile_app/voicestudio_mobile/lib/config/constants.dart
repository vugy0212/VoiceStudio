class AppConstants {
  static const String defaultServerUrl = 'http://127.0.0.1:3900';
  static const String defaultLocalUrl = 'http://192.168.50.175:3900';
  static const String defaultRemoteUrl = 'https://studiovoice.trustshome.org';
  static const String defaultCfClientId = '0f22a8ec4a1a9f59ad9ee99b79229b11.access';
  static const String defaultCfClientSecret = 'cfast_GRtedQFtqybBNwPFPpC6HtpUQpe2L3TnU0LN5Qrr0a1d1667';

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

  static const List<double> availableSpeeds = [0.8, 1.0, 1.25, 1.5, 2.0];
  static const List<String> availableLanguages = ['Auto', 'Croatian', 'English', 'Serbian', 'German', 'Italian', 'Spanish'];

  static const List<Map<String, String>> emotionPresets = [
    {'label': 'Normal', 'prompt': ''},
    {'label': 'Whisper', 'prompt': 'whisper'},
    {'label': 'Deep Voice', 'prompt': 'low pitch'},
    {'label': 'High Pitch', 'prompt': 'high pitch'},
    {'label': 'Young Adult', 'prompt': 'young adult'},
    {'label': 'Elderly', 'prompt': 'elderly'},
    {'label': 'Moderate', 'prompt': 'moderate pitch'},
    {'label': 'Whisper & Low', 'prompt': 'whisper, low pitch'},
  ];
}
