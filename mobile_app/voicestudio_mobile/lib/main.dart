import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'services/storage_service.dart';
import 'services/api_client.dart';
import 'services/audio_service.dart';
import 'services/recorder_service.dart';
import 'state/app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/home_tts_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final storage = await StorageService.init();
  final api = ApiClient(storage);
  final audio = AudioService();
  final recorder = RecorderService();

  final appState = AppState(
    storage: storage,
    api: api,
    audio: audio,
    recorder: recorder,
  );

  await appState.init();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const VoiceStudioApp(),
    ),
  );
}

class VoiceStudioApp extends StatelessWidget {
  const VoiceStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isApproved = context.select<AppState, bool>((s) => s.isApprovedUser);

    return MaterialApp(
      title: 'VoiceStudio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: isApproved ? const HomeTtsScreen() : const AuthScreen(),
    );
  }
}
