import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;

  AudioRecorder get recorder => _audioRecorder;

  Future<bool> hasPermission() async {
    return await _audioRecorder.hasPermission();
  }

  Future<bool> isRecording() async {
    return await _audioRecorder.isRecording();
  }

  Future<void> startRecording() async {
    final hasPerm = await hasPermission();
    if (!hasPerm) {
      throw Exception('Microphone permission not granted');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentRecordingPath = '${tempDir.path}/voice_sample_$timestamp.m4a';

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentRecordingPath!,
    );
  }

  Future<String?> stopRecording() async {
    final path = await _audioRecorder.stop();
    return path ?? _currentRecordingPath;
  }

  Future<Amplitude> getAmplitude() async {
    return await _audioRecorder.getAmplitude();
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}
