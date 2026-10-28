import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class WavUtils {
  /// Converts raw 16-bit PCM little-endian byte array to standard RIFF WAVE bytes
  static Uint8List pcmToWav(Uint8List pcmBytes, {int sampleRate = 24000, int channels = 1}) {
    final byteRate = sampleRate * channels * 2;
    final totalDataLen = pcmBytes.length;
    final totalAudioLen = totalDataLen + 36;
    final header = Uint8List(44);
    final view = ByteData.view(header.buffer);

    // RIFF chunk descriptor
    header.setRange(0, 4, 'RIFF'.codeUnits);
    view.setUint32(4, totalAudioLen, Endian.little);
    header.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt sub-chunk
    header.setRange(12, 16, 'fmt '.codeUnits);
    view.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    view.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    view.setUint16(22, channels, Endian.little); // NumChannels
    view.setUint32(24, sampleRate, Endian.little); // SampleRate
    view.setUint32(28, byteRate, Endian.little); // ByteRate
    view.setUint16(32, channels * 2, Endian.little); // BlockAlign
    view.setUint16(34, 16, Endian.little); // BitsPerSample

    // data sub-chunk
    header.setRange(36, 40, 'data'.codeUnits);
    view.setUint32(40, totalDataLen, Endian.little);

    final wavBytes = Uint8List(44 + totalDataLen);
    wavBytes.setRange(0, 44, header);
    wavBytes.setRange(44, wavBytes.length, pcmBytes);
    return wavBytes;
  }

  /// Extracts PCM payload and sample rate from a WAV byte buffer
  static ({Uint8List pcm, int sampleRate}) extractPcmFromWav(Uint8List wavBytes) {
    if (wavBytes.length <= 44) {
      return (pcm: Uint8List(0), sampleRate: 24000);
    }
    final view = ByteData.view(wavBytes.buffer, wavBytes.offsetInBytes, wavBytes.lengthInBytes);
    int sampleRate = 24000;
    try {
      final sr = view.getUint32(24, Endian.little);
      if (sr >= 8000 && sr <= 96000) sampleRate = sr;
    } catch (_) {}

    // Find 'data' chunk offset (usually at 36, data starts at 44)
    int dataStart = 44;
    for (int i = 12; i < wavBytes.length - 8; i++) {
      if (wavBytes[i] == 0x64 && // 'd'
          wavBytes[i + 1] == 0x61 && // 'a'
          wavBytes[i + 2] == 0x74 && // 't'
          wavBytes[i + 3] == 0x61) { // 'a'
        dataStart = i + 8;
        break;
      }
    }
    if (dataStart >= wavBytes.length) dataStart = 44;
    return (pcm: wavBytes.sublist(dataStart), sampleRate: sampleRate);
  }

  /// Stitches multiple WAV files into a single master WAV file with optional silence pauses (in ms)
  static Future<({File file, double durationSeconds})> stitchWavFiles(
    List<File> files, {
    List<int>? pausesMsAfter,
    String prefix = 'dialogue',
  }) async {
    int sampleRate = 24000;
    final List<Uint8List> chunks = [];

    for (int i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      final extracted = extractPcmFromWav(bytes);
      if (i == 0) sampleRate = extracted.sampleRate;
      chunks.add(extracted.pcm);

      final pauseMs = (pausesMsAfter != null && i < pausesMsAfter.length) ? pausesMsAfter[i] : 350;
      if (pauseMs > 0 && i < files.length - 1) {
        int silenceBytes = ((sampleRate * pauseMs) ~/ 1000) * 2;
        if (silenceBytes.isOdd) silenceBytes++;
        chunks.add(Uint8List(silenceBytes));
      }
    }

    final totalLen = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final combinedPcm = Uint8List(totalLen);
    int offset = 0;
    for (final c in chunks) {
      combinedPcm.setRange(offset, offset + c.length, c);
      offset += c.length;
    }

    final fullWav = pcmToWav(combinedPcm, sampleRate: sampleRate);
    final tempDir = await getTemporaryDirectory();
    final out = File('${tempDir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.wav');
    await out.writeAsBytes(fullWav, flush: true);
    final duration = totalLen / (sampleRate * 2);
    return (file: out, durationSeconds: duration);
  }

  /// Writes PCM bytes as a temporary WAV file on device
  static Future<File> writeChunkAsWav(
    Uint8List pcmBytes, {
    required String prefix,
    required int seq,
    int sampleRate = 24000,
    int channels = 1,
  }) async {
    final wavBytes = pcmToWav(pcmBytes, sampleRate: sampleRate, channels: channels);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${prefix}_chunk_$seq.wav');
    return await file.writeAsBytes(wavBytes, flush: true);
  }

  /// Cleans temporary audio files created during streaming or previewing older than [maxAgeHours]
  static Future<void> cleanOldTempFiles({int maxAgeHours = 4}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final entities = tempDir.listSync();
      final cutoff = DateTime.now().subtract(Duration(hours: maxAgeHours));

      for (final entity in entities) {
        if (entity is File) {
          final filename = entity.uri.pathSegments.last;
          if (filename.startsWith('stream_') ||
              filename.startsWith('synth_') ||
              filename.startsWith('dialogue_') ||
              filename.startsWith('convert_') ||
              filename.startsWith('clean_') ||
              filename.startsWith('voice_sample_')) {
            try {
              final stat = entity.statSync();
              if (stat.modified.isBefore(cutoff)) {
                entity.deleteSync();
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Non-critical cleanup
    }
  }
}
