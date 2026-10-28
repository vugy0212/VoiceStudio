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
  final List<File>? chunkFiles;

  GenerateResult({
    required this.audioFile,
    this.audioPath,
    this.duration,
    this.genTime,
    this.chunkFiles,
  });
}

class ConvertResult {
  final File audioFile;
  final String recognizedText;
  final double duration;
  final double? genTime;
  final String id;

  ConvertResult({
    required this.audioFile,
    required this.recognizedText,
    required this.duration,
    this.genTime,
    required this.id,
  });
}

class ArchetypeItem {
  final String id;
  final String name;
  final String gender;
  final String age;
  final String accent;
  final String useCase;
  final String instruct;
  final String language;
  final bool featured;

  const ArchetypeItem({
    required this.id,
    required this.name,
    required this.gender,
    required this.age,
    required this.accent,
    required this.useCase,
    required this.instruct,
    required this.language,
    this.featured = false,
  });

  factory ArchetypeItem.fromJson(Map<String, dynamic> json) {
    return ArchetypeItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Arhetip',
      gender: json['gender']?.toString() ?? '',
      age: json['age']?.toString() ?? '',
      accent: json['accent']?.toString() ?? '',
      useCase: json['use_case']?.toString() ?? '',
      instruct: json['instruct']?.toString() ?? '',
      language: json['language']?.toString() ?? 'Auto',
      featured: json['featured'] == true,
    );
  }
}

class GatewayInfo {
  final bool reachable;
  final String backendStatus; // 'RUNNING', 'SLEEPING', 'STARTING', 'DIRECT', 'OFFLINE'
  final int idleSecondsRemaining;
  final int queueLength;
  final int activeGpuJobs;

  const GatewayInfo({
    required this.reachable,
    required this.backendStatus,
    this.idleSecondsRemaining = 0,
    this.queueLength = 0,
    this.activeGpuJobs = 0,
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
          'User-Agent': 'VoiceStudioMobile/1.1 (Android; Mobile)',
          'Accept': 'application/json, */*',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final cfId = _storage.getCfClientId();
          final cfSecret = _storage.getCfClientSecret();

          if (cfId.isNotEmpty) {
            options.headers['CF-Access-Client-Id'] = cfId;
          }
          if (cfSecret.isNotEmpty) {
            options.headers['CF-Access-Client-Secret'] = cfSecret;
          }

          final user = _storage.getCurrentUser();
          if (user != null) {
            options.headers['X-VS-User-Id'] = user.uid;
            options.headers['X-VS-User-Role'] = user.role;
            options.headers['X-VS-User-Email'] = user.email;
            options.headers['X-VS-Session-Token'] = user.sessionToken;
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
    return url;
  }

  String get connectionMode => _storage.getConnectionMode();

  String get baseUrl {
    if (_activeBaseUrl != null && _activeBaseUrl!.isNotEmpty) return _activeBaseUrl!;
    if (connectionMode == 'local') return localBaseUrl;
    if (connectionMode == 'remote') return remoteBaseUrl.isNotEmpty ? remoteBaseUrl : localBaseUrl;
    return remoteBaseUrl.isNotEmpty ? remoteBaseUrl : localBaseUrl;
  }

  String get activeBaseUrl => baseUrl;

  bool get isUsingLocalUrl => baseUrl == localBaseUrl || baseUrl == 'http://127.0.0.1:3900';

  void resetActiveBaseUrl() {
    _activeBaseUrl = null;
  }

  /// Non-waking lightweight probe using /gateway/status first, fallback to /profiles
  Future<GatewayInfo> probeUrl(String targetBaseUrl, {Duration timeout = const Duration(milliseconds: 1500)}) async {
    if (targetBaseUrl.trim().isEmpty) {
      return const GatewayInfo(reachable: false, backendStatus: 'OFFLINE');
    }
    try {
      final res = await _dio.get(
        '$targetBaseUrl/gateway/status',
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (_isCloudflareHtml(res)) {
        throw Exception('Cloudflare Access autentifikacija nije prošla.');
      }

      if (res.statusCode == 200 && res.data is Map) {
        final map = res.data as Map;
        final status = map['status']?.toString() ?? 'RUNNING';
        final idleRem = (map['idle_seconds_remaining'] as num?)?.toInt() ?? 0;
        final qLen = (map['queue_length'] as num?)?.toInt() ?? 0;
        final activeJobs = (map['active_gpu_jobs'] as num?)?.toInt() ?? 0;
        return GatewayInfo(
          reachable: true,
          backendStatus: status,
          idleSecondsRemaining: idleRem,
          queueLength: qLen,
          activeGpuJobs: activeJobs,
        );
      }

      if (res.statusCode == 404) {
        final resDirect = await _dio.get(
          '$targetBaseUrl/profiles',
          options: Options(
            sendTimeout: timeout,
            receiveTimeout: timeout,
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        if (resDirect.statusCode == 200 && resDirect.data is List && !_isCloudflareHtml(resDirect)) {
          return const GatewayInfo(reachable: true, backendStatus: 'DIRECT');
        }
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 302) {
        throw Exception('Cloudflare Access odbio zahtjev (302).');
      } else if (status == 502) {
        throw Exception('Poslužitelj trenutno nije pokrenut (502).');
      }
    } catch (e) {
      if (e.toString().contains('Cloudflare')) rethrow;
    }

    return const GatewayInfo(reachable: false, backendStatus: 'OFFLINE');
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

    // Auto mode: probe configured local URL without waking sleeping backend
    if (_storage.getLocalUrl().trim().isNotEmpty) {
      try {
        final info = await probeUrl(localBaseUrl, timeout: const Duration(milliseconds: 1200));
        if (info.reachable) {
          _activeBaseUrl = localBaseUrl;
          return _activeBaseUrl!;
        }
      } catch (_) {}
    }

    // Also check USB reverse (127.0.0.1:3900)
    try {
      final infoUsb = await probeUrl('http://127.0.0.1:3900', timeout: const Duration(milliseconds: 900));
      if (infoUsb.reachable) {
        _activeBaseUrl = 'http://127.0.0.1:3900';
        return _activeBaseUrl!;
      }
    } catch (_) {}

    _activeBaseUrl = remoteBaseUrl.isNotEmpty ? remoteBaseUrl : localBaseUrl;
    return _activeBaseUrl!;
  }

  String getAudioFileUrl(String filename) {
    final cleanName = filename.split('/').last.split('\\').last;
    return '$baseUrl/audio/$cleanName';
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
    final user = _storage.getCurrentUser();
    if (user != null) {
      headers['X-VS-User-Id'] = user.uid;
      headers['X-VS-User-Role'] = user.role;
      headers['X-VS-Session-Token'] = user.sessionToken;
    }
    return headers;
  }

  bool _isCloudflareHtml(Response response) {
    if (response.realUri.toString().contains('cloudflareaccess.com')) return true;
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.contains('text/html')) return true;
    if (response.data is String && (response.data as String).contains('cloudflareaccess')) return true;
    return false;
  }

  Future<GatewayInfo> checkGatewayConnection() async {
    await resolveActiveBaseUrl();
    final timeout = isUsingLocalUrl
        ? const Duration(milliseconds: 2500)
        : const Duration(milliseconds: 6000);
    return await probeUrl(baseUrl, timeout: timeout);
  }

  Future<bool> checkConnection() async {
    final info = await checkGatewayConnection();
    return info.reachable;
  }

  Future<bool> wakeGateway() async {
    try {
      final res = await _dio.post(
        '$baseUrl/gateway/wake',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 65),
        ),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sleepGateway() async {
    try {
      final res = await _dio.post(
        '$baseUrl/gateway/sleep',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> testEndpoints() async {
    bool localOk = false;
    int? localPing;
    String? localError;
    String? localBackendState;

    bool remoteOk = false;
    int? remotePing;
    String? remoteError;
    String? remoteBackendState;

    try {
      final sw = Stopwatch()..start();
      final info = await probeUrl(localBaseUrl, timeout: const Duration(seconds: 2));
      sw.stop();
      if (info.reachable) {
        localOk = true;
        localPing = sw.elapsedMilliseconds;
        localBackendState = info.backendStatus;
      } else {
        localError = 'Nije dostupno (izvan lokalne mreže)';
      }
    } catch (e) {
      localError = e.toString().replaceAll('Exception: ', '');
    }

    try {
      final sw = Stopwatch()..start();
      final info = await probeUrl(remoteBaseUrl, timeout: const Duration(seconds: 5));
      sw.stop();
      if (info.reachable) {
        remoteOk = true;
        remotePing = sw.elapsedMilliseconds;
        remoteBackendState = info.backendStatus;
      } else {
        remoteError = 'Poslužitelj nije dostupan preko tunela';
      }
    } catch (e) {
      remoteError = e.toString().replaceAll('Exception: ', '').split('\n').first;
    }

    final active = await resolveActiveBaseUrl();

    return {
      'localOk': localOk,
      'localPing': localPing,
      'localError': localError,
      'localState': localBackendState,
      'remoteOk': remoteOk,
      'remotePing': remotePing,
      'remoteError': remoteError,
      'remoteState': remoteBackendState,
      'active': active,
      'isUsingLocal': active == localBaseUrl || active == 'http://127.0.0.1:3900',
    };
  }

  Future<List<VoiceProfile>> getProfiles() async {
    try {
      final response = await _dio.get('$baseUrl/profiles');
      if (_isCloudflareHtml(response)) {
        throw Exception('Cloudflare Access prijava potrebna.');
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

  Future<GenerateResult> generateSpeechStream({
    required String text,
    String? profileId,
    double speed = 1.0,
    String language = 'Auto',
    String? instruct,
    int steps = 16,
    double guidanceScale = 2.0,
    File? refAudioFile,
    CancelToken? cancelToken,
    required void Function(int seq, File chunkWav, int totalChunks) onChunkReady,
  }) async {
    try {
      final mapData = <String, dynamic>{
        'text': text,
        'speed': speed,
        'num_step': steps,
        'guidance_scale': guidanceScale,
        'stream': true,
        'max_chunk_chars': 140,
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
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          contentType: 'multipart/form-data',
        ),
      );

      final streamBody = response.data;
      if (streamBody == null) {
        throw Exception('Poslužitelj je vratio prazan stream odgovor');
      }

      int sampleRate = 24000;
      int totalChunks = 1;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final List<Uint8List> allPcmBytes = [];
      final List<File> chunkFiles = [];
      String? completedAudioPath;
      double? duration;
      double? genTime;

      final lines = streamBody.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (cancelToken?.isCancelled == true) {
          throw DioException.requestCancelled(requestOptions: RequestOptions(), reason: 'Prekinuto od strane korisnika');
        }
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
              chunkFiles.add(chunkWav);
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
        }
      }

      if (allPcmBytes.isEmpty) {
        throw Exception('Poslužitelj nije vratio nijedan audio segment.');
      }

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
        chunkFiles: chunkFiles,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw Exception('Generiranje prekinuto.');
      }
      if (e.response?.statusCode == 429) {
        throw Exception('Poslužitelj je trenutačno preopterećen ili ste dosegnuli dnevni limit.');
      }
      throw Exception('Greška generiranja (stream): ${e.message ?? e}');
    } catch (e) {
      throw Exception('Greška generiranja (stream): $e');
    }
  }

  Future<GenerateResult> generateSpeech({
    required String text,
    String? profileId,
    double speed = 1.0,
    String language = 'Auto',
    String? instruct,
    int steps = 16,
    double guidanceScale = 2.0,
    File? refAudioFile,
    CancelToken? cancelToken,
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
        cancelToken: cancelToken,
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
        throw Exception('Poslužitelj je vratio status ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw Exception('Generiranje prekinuto.');
      }
      if (e.response?.statusCode == 429) {
        throw Exception('Poslužitelj je trenutačno preopterećen ili ste dosegnuli dnevni limit.');
      }
      throw Exception('Greška generiranja: ${e.message ?? e}');
    } catch (e) {
      throw Exception('Greška generiranja: $e');
    }
  }

  Future<File> downloadAudioFile(String filename) async {
    final url = getAudioFileUrl(filename);
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.statusCode == 200 && response.data != null) {
      final tempDir = await getTemporaryDirectory();
      final cleanName = filename.split('/').last.split('\\').last;
      final file = File('${tempDir.path}/hist_$cleanName');
      await file.writeAsBytes(response.data!, flush: true);
      return file;
    }
    throw Exception('Preuzimanje audio datoteke nije uspjelo.');
  }

  Future<VoiceProfile> createProfile({
    required String name,
    required String audioPath,
  }) async {
    try {
      final ext = audioPath.split('.').last.toLowerCase();
      final uploadName = ext.isNotEmpty ? 'voice_sample.$ext' : 'voice_sample.wav';
      final formData = FormData.fromMap({
        'name': name,
        'kind': 'clone',
        'ref_audio': await MultipartFile.fromFile(
          audioPath,
          filename: uploadName,
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
      throw Exception('Poslužitelj vratio ${response.statusCode}: ${response.data}');
    } catch (e) {
      throw Exception('Greška kreiranja profila: $e');
    }
  }

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

  Future<bool> deleteProfile(String profileId) async {
    try {
      final response = await _dio.delete('$baseUrl/profiles/$profileId');
      return response.statusCode == 200;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('Nemate ovlasti za brisanje zajedničkog (javnog) glasa.');
      }
      throw Exception('Greška brisanja profila: ${e.message ?? e}');
    } catch (e) {
      throw Exception('Greška brisanja profila: $e');
    }
  }

  Future<ConvertResult> convertSpeech({
    required File sourceAudio,
    required String profileId,
    bool matchDuration = true,
    CancelToken? cancelToken,
  }) async {
    try {
      final ext = sourceAudio.path.split('.').last.toLowerCase();
      final uploadName = ext.isNotEmpty ? 'source.$ext' : 'source.wav';

      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(sourceAudio.path, filename: uploadName),
        'profile_id': profileId,
        'match_duration': matchDuration,
      });

      final response = await _dio.post(
        '$baseUrl/convert',
        data: formData,
        cancelToken: cancelToken,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final audioUrlPath = data['audio_url']?.toString() ?? '';
        final text = data['text']?.toString() ?? '';
        final duration = (data['duration_s'] as num?)?.toDouble() ?? 0.0;
        final genTime = (data['gen_time_s'] as num?)?.toDouble();
        final id = data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

        final fullAudioUrl = audioUrlPath.startsWith('http')
            ? audioUrlPath
            : '$baseUrl${audioUrlPath.startsWith("/") ? "" : "/"}$audioUrlPath';

        final wavResp = await _dio.get<List<int>>(
          fullAudioUrl,
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.bytes),
        );

        final tempDir = await getTemporaryDirectory();
        final outFile = File('${tempDir.path}/convert_${DateTime.now().millisecondsSinceEpoch}.wav');
        await outFile.writeAsBytes(wavResp.data!, flush: true);

        return ConvertResult(
          audioFile: outFile,
          recognizedText: text,
          duration: duration,
          genTime: genTime,
          id: id,
        );
      }
      throw Exception('Poslužitelj je vratio status ${response.statusCode}');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw Exception('Pretvorba glasa prekinuta.');
      }
      final detail = e.response?.data is Map ? (e.response?.data['detail']?.toString()) : null;
      throw Exception(detail ?? 'Greška pri pretvorbi glasa: ${e.message ?? e}');
    } catch (e) {
      throw Exception('Greška pri pretvorbi glasa: $e');
    }
  }

  Future<File> cleanAudio(File rawAudio) async {
    try {
      final ext = rawAudio.path.split('.').last.toLowerCase();
      final uploadName = ext.isNotEmpty ? 'raw.$ext' : 'raw.wav';

      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(rawAudio.path, filename: uploadName),
      });

      final response = await _dio.post<List<int>>(
        '$baseUrl/clean-audio',
        data: formData,
        options: Options(
          responseType: ResponseType.bytes,
          contentType: 'multipart/form-data',
          receiveTimeout: const Duration(seconds: 240),
        ),
      );

      if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final cleanedFile = File('${tempDir.path}/clean_${DateTime.now().millisecondsSinceEpoch}.wav');
        await cleanedFile.writeAsBytes(response.data!, flush: true);
        return cleanedFile;
      }
      throw Exception('Poslužitelj nije vratio očišćeni audio zapis.');
    } catch (e) {
      throw Exception('Greška čišćenja šuma: $e');
    }
  }

  Future<Map<String, dynamic>> describeVoice(String description) async {
    try {
      final response = await _dio.post(
        '$baseUrl/design/describe',
        data: {'description': description},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('Neispravan odgovor za dizajn glasa.');
    } catch (e) {
      throw Exception('Greška analize opisa glasa: $e');
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
      final formData = FormData.fromMap({
        'name': name,
        'kind': 'design',
        'vd_states': jsonEncode(vdStates),
        'instruct': instruct,
        'language': language,
        if (sampleScript.trim().isNotEmpty) 'ref_text': sampleScript.trim(),
      });

      final response = await _dio.post(
        '$baseUrl/profiles',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return VoiceProfile.fromJson(response.data as Map<String, dynamic>);
      }
      throw Exception('Poslužitelj vratio ${response.statusCode}: ${response.data}');
    } catch (e) {
      throw Exception('Greška kreiranja dizajniranog profila: $e');
    }
  }

  Future<List<ArchetypeItem>> getArchetypes({
    String? query,
    String? gender,
    int limit = 80,
  }) async {
    try {
      final queryParams = <String, dynamic>{'limit': limit};
      if (query != null && query.trim().isNotEmpty) queryParams['q'] = query.trim();
      if (gender != null && gender.trim().isNotEmpty && gender != 'All') {
        queryParams['gender'] = gender.toLowerCase();
      }

      final response = await _dio.get(
        '$baseUrl/archetypes',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data is Map) {
        final items = (response.data as Map)['items'];
        if (items is List) {
          return items
              .map((item) => ArchetypeItem.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
      return [];
    } catch (e) {
      throw Exception('Greška dohvaćanja kataloga arhetipova: $e');
    }
  }

  String getArchetypePreviewUrl(String archetypeId) {
    return '$baseUrl/archetypes/$archetypeId/preview';
  }

  Future<VoiceProfile> useArchetype(String archetypeId, {String? customName}) async {
    try {
      final response = await _dio.post(
        '$baseUrl/archetypes/$archetypeId/use',
        queryParameters: customName != null && customName.trim().isNotEmpty
            ? {'name': customName.trim()}
            : null,
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return VoiceProfile.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
      throw Exception('Poslužitelj vratio ${response.statusCode}');
    } catch (e) {
      throw Exception('Greška aktivacije arhetipa: $e');
    }
  }
}
