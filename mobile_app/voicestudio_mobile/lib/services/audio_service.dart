import 'dart:io';
import 'package:just_audio/just_audio.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  // ignore: deprecated_member_use
  ConcatenatingAudioSource? _streamPlaylist;
  bool _isStreamingActive = false;
  File? _pendingCompleteFile;

  AudioPlayer get player => _player;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<double> get speedStream => _player.speedStream;

  Duration get currentPosition => _player.position;
  Duration? get totalDuration => _player.duration;
  bool get isPlaying => _player.playing;
  bool get isStreamingActive => _isStreamingActive;
  String? _currentSource;
  String? get currentSource => _currentSource;

  Future<void> playFile(File file) async {
    _isStreamingActive = false;
    _streamPlaylist = null;
    _currentSource = file.path;
    await _player.stop();
    await _player.setFilePath(file.path);
    await _player.play();
  }

  Future<void> playUrl(String url, {Map<String, String>? headers}) async {
    _isStreamingActive = false;
    _streamPlaylist = null;
    _currentSource = url;
    await _player.stop();
    await _player.setUrl(url, headers: headers);
    await _player.play();
  }

  /// Prepare audio player for live streaming chunks
  Future<void> prepareStreaming() async {
    await _player.stop();
    _isStreamingActive = true;
    // ignore: deprecated_member_use
    _streamPlaylist = ConcatenatingAudioSource(children: []);
  }

  /// Add a synthesized chunk to the live playback playlist
  Future<void> addStreamChunk(File chunkFile) async {
    if (_streamPlaylist == null) {
      await prepareStreaming();
    }
    await _streamPlaylist!.add(AudioSource.file(chunkFile.path));
    if (!_player.playing) {
      await _player.setAudioSource(_streamPlaylist!);
      await _player.play();
    }
  }

  /// Finalize streaming and prepare the complete WAV for scrubber/replay
  Future<void> finalizeStreaming(File completeFile, {List<File>? chunkFiles}) async {
    _pendingCompleteFile = completeFile;
    _isStreamingActive = false;

    // Seamlessly swap the chunked playlist with the single full master audio file
    try {
      final currentPos = _player.position;
      final wasPlaying = _player.playing;

      await _player.setFilePath(completeFile.path, initialPosition: currentPos);
      if (wasPlaying) {
        await _player.play();
      }
      _streamPlaylist = null;
      _cleanupChunks(chunkFiles);
    } catch (e) {
      // Log error for debugging streaming transitions
      // Fallback: wait for playlist end
      _player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      ).then((_) async {
        if (_pendingCompleteFile != null && !_player.playing) {
          await _player.setFilePath(_pendingCompleteFile!.path);
          _streamPlaylist = null;
          _cleanupChunks(chunkFiles);
        }
      }).catchError((_) {});
    }
  }

  void _cleanupChunks(List<File>? chunks) {
    if (chunks == null || chunks.isEmpty) return;
    for (final file in chunks) {
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
  }

  Future<void> stop() async {
    _isStreamingActive = false;
    await _player.stop();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> seekRelative(Duration delta) async {
    final newPos = _player.position + delta;
    if (newPos < Duration.zero) {
      await _player.seek(Duration.zero);
    } else if (_player.duration != null && newPos > _player.duration!) {
      await _player.seek(_player.duration);
    } else {
      await _player.seek(newPos);
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  void dispose() {
    _player.dispose();
  }
}
