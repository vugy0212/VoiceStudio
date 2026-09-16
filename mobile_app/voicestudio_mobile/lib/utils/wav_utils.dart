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
}
