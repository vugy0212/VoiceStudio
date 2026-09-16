import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/voice_profile.dart';
import '../models/generation_history.dart';
import '../utils/wav_utils.dart';
import 'storage_service.dart';

class GenerateResult {
  final File audioFile;
  final String? audioPath;
  final double? duration;
  final double? genTime;

  GenerateResult({
    required this.audioFile,
    this.audioPath,
    this.duration,
    this.genTime,
  });
}

class ApiClient {
  final StorageService _storage;
  late final Dio _dio;
  String? _activeBaseUrl;

  ApiClient(this._storage) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        headers: {
          'User-Agent': 'VoiceStudioMobile/1.0 (Android; Mobile)',
          'Accept': 'application/json, */*',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Inject Cloudflare Access Service Token headers
          final cfId = _storage.getCfClientId();
          final cfSecret = _storage.getCfClientSecret();

          if (cfId.isNotEmpty) {
            options.headers['CF-Access-Client-Id'] = cfId;
          }
          if (cfSecret.isNotEmpty) {
            options.headers['CF-Access-Client-Secret'] = cfSecret;
          }

          handler.next(options);
        },
      ),
    );
  }

  String get localBaseUrl {
    String url = _storage.getLocalUrl().trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url.isEmpty ? 'http://127.0.0.1:3900' : url;
  }

  String get remoteBaseUrl {
    String url = _storage.getRemoteUrl().trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url.isEmpty ? 'https://studiovoice.trustshome.org' : url;
  }

  String get connectionMode => _storage.getConnectionMode();

  String get baseUrl {
    if (_activeBaseUrl != null) return _activeBaseUrl!;
    if (connectionMode == 'local') return localBaseUrl;
    if (connectionMode == 'remote') return remoteBaseUrl;
    // Default fallback in auto mode: local first
    return localBaseUrl;
  }

  String get activeBaseUrl => baseUrl;

  bool get isUsingLocalUrl => baseUrl == localBaseUrl;

  void resetActiveBaseUrl() {
    _activeBaseUrl = null;
  }

  Future<String> resolveActiveBaseUrl() async {
    final mode = connectionMode;
    if (mode == 'local') {
      _activeBaseUrl = localBaseUrl;
      return _activeBaseUrl!;
    }
    if (mode == 'remote') {
      _activeBaseUrl = remoteBaseUrl;
      return _activeBaseUrl!;
    }

    // Auto mode: test configured local URL first with short timeout (1500ms)
    try {
      final res = await _dio.get(
        '$localBaseUrl/profiles',
        options: Options(
          sendTimeout: const Duration(milliseconds: 1500),
          receiveTimeout: const Duration(milliseconds: 1500),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (res.statusCode == 200 && res.data is List && !_isCloudflareHtml(res)) {
        _activeBaseUrl = localBaseUrl;
        return _activeBaseUrl!;
      }
    } catch (_) {}

    // If localBaseUrl wasn't 127.0.0.1, also check USB reverse (127.0.0.1:3900)
    if (!localBaseUrl.contains('127.0.0.1')) {
      try {
        final resUsb = await _dio.get(
          'http://127.0.0.1:3900/profiles',
          options: Options(
            sendTimeout: const Duration(milliseconds: 1200),
            receiveTimeout: const Duration(milliseconds: 1200),
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        if (resUsb.statusCode == 200 && resUsb.data is List && !_isCloudflareHtml(resUsb)) {
          _activeBaseUrl = 'http://127.0.0.1:3900';
          return _activeBaseUrl!;
        }
      } catch (_) {}
    }

    _activeBaseUrl = remoteBaseUrl;
    return _activeBaseUrl!;
  }

  String getAudioFileUrl(String filename) {
    return '$baseUrl/audio/$filename';
  }

  String getProfileAudioUrl(String profileId) {
    return '$baseUrl/profiles/$profileId/audio';
  }

  Map<String, String> getAuthHeaders() {
    final headers = <String, String>{};
    final cfId = _storage.getCfClientId();
    final cfSecret = _storage.getCfClientSecret();
    if (cfId.isNotEmpty) headers['CF-Access-Client-Id'] = cfId;
    if (cfSecret.isNotEmpty) headers['CF-Access-Client-Secret'] = cfSecret;
    return headers;
  }

  bool _isCloudflareHtml(Response response) {
    if (response.realUri.toString().contains('cloudflareaccess.com')) return true;
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.contains('text/html')) return true;
    if (response.data is String && (response.data as String).contains('cloudflareaccess')) return true;
    return false;
  }

  /// Check server connectivity with auto URL fallback
  Future<bool> checkConnection() async {
    try {
      await resolveActiveBaseUrl();
      final resProfiles = await _dio.get(
        '$baseUrl/profiles',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (_isCloudflareHtml(resProfiles)) {
        throw Exception('Cloudflare Access login potreban (302). Unesite CF Service Token u Postavkama.');
      }
      return resProfiles.statusCode == 200 && resProfiles.data is List;
    } on DioException catch (e) {
      if (e.response?.statusCode == 302 || e.type == DioExceptionType.badResponse) {
        throw Exception('Cloudflare odbio zahtjev (302 PIN redirect). Dodajte CF Service Token.');
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Test both endpoints for Settings diagnostics
  Future<Map<String, dynamic>> testEndpoints() async {
    bool localOk = false;
    int? localPing;
    String? localError;

    bool remoteOk = false;
    int? remotePing;
    String? remoteError;

    // Test Local
    try {
      final sw = Stopwatch()..start();
      final res = await _dio.get(
        '$localBaseUrl/profiles',
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      sw.stop();
      if (_isCloudflareHtml(res)) {
        localError = 'Cloudflare redirect na lokalnoj adresi';
      } else if (res.statusCode == 200 && res.data is List) {
        localOk = true;
        localPing = sw.elapsedMilliseconds;
      } else {
        localError = 'Status ${res.statusCode}';
      }
    } catch (e) {
      localError = 'Nije dostupno (izvan lokalne mreže)';
    }

    // Test Remote
    try {
      final sw = Stopwatch()..start();
      final res = await _dio.get(
        '$remoteBaseUrl/profiles',
        options: Options(
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      sw.stop();
      if (_isCloudflareHtml(res)) {
        remoteError = 'Traži se Cloudflare Service Token (302)';
      } else if (res.statusCode == 200 && res.data is List) {
        remoteOk = true;
        remotePing = sw.elapsedMilliseconds;
      } else {
        remoteError = 'Status ${res.statusCode}';
      }
    } catch (e) {
      remoteError = 'Neuspješno spajanje: ${e.toString().split('\n').first}';
    }

    final active = await resolveActiveBaseUrl();

    return {
      'localOk': localOk,
      'localPing': localPing,
      'localError': localError,
      'remoteOk': remoteOk,
      'remotePing': remotePing,
      'remoteError': remoteError,
      'active': active,
      'isUsingLocal': active == localBaseUrl,
    };
  }

  /// Fetch all voice profiles
  Future<List<VoiceProfile>> getProfiles() async {
    try {
      final response = await _dio.get('$baseUrl/profiles');
      if (_isCloudflareHtml(response)) {
        throw Exception('Cloudflare Access login potreban. Postavite CF Service Token u Postavkama.');
      }
      if (response.statusCode == 200 && response.data is List) {
        final List list = response.data;
        return list.map((item) => VoiceProfile.fromJson(item as Map<String, dynamic>)).toList();
      }
      return [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 302) {
        throw Exception('Cloudflare Access PIN login required (302 redirect).');
      }
      throw Exception('Greška dohvaćanja profila: ${e.message ?? e}');
    } catch (e) {
      throw Exception('Greška dohvaćanja profila: $e');
    }
  }

  /// Streaming speech generation with low-latency chunk delivery
  Future<GenerateResult> generateSpeechStream({
    required String text,
    String? profileId,
    double speed = 1.0,
    String language = 'Auto',
    String? instruct,
    int steps = 16,
    double guidanceScale = 2.0,
    File? refAudioFile,
    required void Function(int seq, File chunkWav, int totalChunks) onChunkReady,
  }) async {
    try {
      final mapData = <String, dynamic>{
        'text': text,
        'speed': speed,
        'num_step': steps,
        'guidance_scale': guidanceScale,
        'stream': true,
        'max_chunk_chars': 140, // Trigger sentence-level streaming for instant TTFA
      };

      if (language != 'Auto') {
        mapData['language'] = language;
      }

      if (instruct != null && instruct.trim().isNotEmpty) {
        mapData['instruct'] = instruct.trim();
      }

      if (profileId != null && profileId.isNotEmpty) {
        mapData['profile_id'] = profileId;
      } else if (refAudioFile != null) {
        mapData['ref_audio'] = await MultipartFile.fromFile(
          refAudioFile.path,
          filename: 'reference.wav',
        );
      }

      final formData = FormData.fromMap(mapData);
      final response = await _dio.post<ResponseBody>(
        '$baseUrl/generate',
        data: formData,
        options: Options(
          responseType: ResponseType.stream,
          contentType: 'multipart/form-data',
        ),
      );

      final streamBody = response.data;
      if (streamBody == null) {
        throw Exception('Server returned empty streaming response');
      }

      int sampleRate = 24000;
      int totalChunks = 1;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final List<Uint8List> allPcmBytes = [];
      String? completedAudioPath;
      double? duration;
      double? genTime;

      final lines = streamBody.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          final type = data['type'] as String?;

          if (type == 'start') {
            sampleRate = (data['sample_rate'] as num?)?.toInt() ?? 24000;
            totalChunks = (data['total_chunks'] as num?)?.toInt() ?? 1;
          } else if (type == 'chunk') {
            final seq = (data['seq'] as num?)?.toInt() ?? 0;
            final pcmB64 = data['pcm'] as String? ?? '';
            if (pcmB64.isNotEmpty) {
              final pcmBytes = base64Decode(pcmB64);
              allPcmBytes.add(pcmBytes);

              final chunkWav = await WavUtils.writeChunkAsWav(
                pcmBytes,
                prefix: 'stream_$timestamp',
                seq: seq,
                sampleRate: sampleRate,
              );
              onChunkReady(seq, chunkWav, totalChunks);
            }
          } else if (type == 'done') {
            completedAudioPath = data['audio_path'] as String?;
            duration = (data['duration'] as num?)?.toDouble();
            genTime = (data['gen_time'] as num?)?.toDouble();
          } else if (type == 'error') {
            final detail = data['detail'] ?? 'Greška prilikom generiranja na serveru';
            throw Exception(detail);
          }
        } catch (e) {
          if (e is Exception && e.toString().contains('Exception:')) rethrow;
          // Ignore individual JSON line parse irregularities
        }
      }

      if (allPcmBytes.isEmpty) {
        throw Exception('Server nije vratio nijedan audio segment (provjerite odabrani stil ili profil)');
      }

      // Assemble complete WAV file from all PCM chunks
      final int totalLength = allPcmBytes.fold(0, (acc, b) => acc + b.length);
      final completePcm = Uint8List(totalLength);
      int offset = 0;
      for (final b in allPcmBytes) {
        completePcm.setRange(offset, offset + b.length, b);
        offset += b.length;
      }

      final completeWav = WavUtils.pcmToWav(completePcm, sampleRate: sampleRate);
      final tempDir = await getTemporaryDirectory();
      final fullAudioFile = File('${tempDir.path}/synth_stream_$timestamp.wav');
      await fullAudioFile.writeAsBytes(completeWav, flush: true);

      return GenerateResult(
        audioFile: fullAudioFile,
        audioPath: completedAudioPath,
        duration: duration ?? (totalLength / (sampleRate * 2)),
        genTime: genTime,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 302 || e.message?.contains('302') == true) {
        throw Exception('Cloudflare blokirao zahtjev (302 redirect). Dodajte CF Service Token u Postavkama.');
      }
      throw Exception('Greška generiranja (stream): ${e.message ?? e}');
    } catch (e) {
      throw Exception('Greška generiranja (stream): $e');
    }
  }

  /// Generate speech via POST /generate (batch mode)
  Future<GenerateResult> generateSpeech({
    required String text,
    String? profileId,
    double speed = 1.0,
    String language = 'Auto',
    String? instruct,
    int steps = 16,
    double guidanceScale = 2.0,
    File? refAudioFile,
  }) async {
    try {
      final mapData = <String, dynamic>{
        'text': text,
        'speed': speed,
        'num_step': steps,
        'guidance_scale': guidanceScale,
        'stream': false,
      };

      if (language != 'Auto') {
        mapData['language'] = language;
      }

      if (instruct != null && instruct.trim().isNotEmpty) {
        mapData['instruct'] = instruct.trim();
      }

      if (profileId != null && profileId.isNotEmpty) {
        mapData['profile_id'] = profileId;
      } else if (refAudioFile != null) {
        mapData['ref_audio'] = await MultipartFile.fromFile(
          refAudioFile.path,
          filename: 'reference.wav',
        );
      }

      final formData = FormData.fromMap(mapData);

      final response = await _dio.post(
        '$baseUrl/generate',
        data: formData,
        options: Options(
          responseType: ResponseType.bytes,
          contentType: 'multipart/form-data',
        ),
      );

      if (response.statusCode == 200 && response.data is List<int>) {
        final Uint8List bytes = Uint8List.fromList(response.data);
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final savedFile = File('${tempDir.path}/synth_$timestamp.wav');
        await savedFile.writeAsBytes(bytes);

        final audioPath = response.headers.value('X-Audio-Path');
        final durStr = response.headers.value('X-Audio-Duration');
        final genTimeStr = response.headers.value('X-Gen-Time');

        return GenerateResult(
          audioFile: savedFile,
          audioPath: audioPath,
          duration: durStr != null ? double.tryParse(durStr) : null,
          genTime: genTimeStr != null ? double.tryParse(genTimeStr) : null,
        );
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 302 || e.message?.contains('302') == true) {
        throw Exception('Cloudflare blokirao zahtjev (302 redirect). Dodajte CF Service Token u Postavkama.');
      }
      throw Exception('Greška generiranja: ${e.message ?? e}');
    } catch (e) {
      throw Exception('Greška generiranja: $e');
    }
  }

  /// Create a new voice profile via POST /profiles
  Future<VoiceProfile> createProfile({
    required String name,
    required String audioPath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'name': name,
        'kind': 'clone',
        'ref_audio': await MultipartFile.fromFile(
          audioPath,
          filename: 'voice_sample.wav',
        ),
      });

      final response = await _dio.post(
        '$baseUrl/profiles',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return VoiceProfile.fromJson(response.data as Map<String, dynamic>);
      }
      throw Exception('Server returned ${response.statusCode}: ${response.data}');
    } catch (e) {
      throw Exception('Greška kreiranja profila: $e');
    }
  }

  /// Get generation history via GET /history
  Future<List<GenerationHistory>> getHistory() async {
    try {
      final response = await _dio.get('$baseUrl/history');
      if (response.statusCode == 200 && response.data is List) {
        final List list = response.data;
        return list.map((item) => GenerationHistory.fromJson(item as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Greška povijesti: $e');
    }
  }

  /// Delete a voice profile via DELETE /profiles/{profile_id}
  Future<bool> deleteProfile(String profileId) async {
    try {
      final response = await _dio.delete('$baseUrl/profiles/$profileId');
      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Greška brisanja profila: $e');
    }
  }
}
