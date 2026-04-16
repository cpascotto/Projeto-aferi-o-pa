import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/patient_model.dart';

class ApiService {
  static const Duration _requestTimeout = Duration(seconds: 20);

  ApiService({
    required this.baseUrl,
    this.fallbackBaseUrl,
  });

  final String baseUrl;
  final String? fallbackBaseUrl;

  Future<List<PatientModel>> fetchPatients() async {
    try {
      final response = await _get('/api/patients');

      if (response.statusCode != 200) {
        throw Exception('Falha ao carregar pacientes: ${response.body}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final patients = (body['patients'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PatientModel.fromJson)
          .toList(growable: false);

      return patients;
    } on SocketException catch (e) {
      throw Exception('${_networkHint()} Detalhe: $e');
    } on TimeoutException {
      throw Exception(
        'O backend demorou mais de ${_requestTimeout.inSeconds}s para responder em $baseUrl.',
      );
    } on http.ClientException catch (e) {
      throw Exception('${_networkHint()} Detalhe: $e');
    }
  }

  Future<PatientModel> registerBasicPatient({
    required String cpf,
  }) async {
    final response = await _postJson(
      '/api/patient/register-basic',
      {
        'cpf': cpf,
      },
    );

    if (response.statusCode != 201) {
      throw Exception(
          'Falha ao cadastrar dados básicos do paciente: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PatientModel.fromJson(body['patient'] as Map<String, dynamic>);
  }

  Future<PatientModel> registerFaceSample({
    required int patientId,
    required String captureType,
    required String faceImageB64,
    required List<double> faceEmbedding,
  }) async {
    final response = await _postJson(
      '/api/patient/register-face-sample',
      {
        'patient_id': patientId,
        'capture_type': captureType,
        'face_image_b64': faceImageB64,
        'face_embedding': faceEmbedding,
      },
    );

    if (response.statusCode != 201) {
      throw Exception('Falha ao cadastrar amostra facial: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PatientModel.fromJson(body['patient'] as Map<String, dynamic>);
  }

  Future<void> registerBloodPressureMeasurement({
    required int patientId,
    required int systolic,
    required int diastolic,
    required int bpm,
    required DateTime measuredAt,
    String? rawPayload,
  }) async {
    final response = await _postJson(
      '/api/patient/blood-pressure-measurements',
      {
        'patient_id': patientId,
        'systolic': systolic,
        'diastolic': diastolic,
        'bpm': bpm,
        'measured_at': measuredAt.toIso8601String(),
        'raw_payload': rawPayload,
      },
    );

    if (response.statusCode != 201) {
      throw Exception('Falha ao cadastrar afericao: ${response.body}');
    }
  }

  Future<int> sendMobileDebugLogs(List<Map<String, dynamic>> logs) async {
    final response = await _postJson(
      '/api/mobile-debug-logs',
      {
        'device_context': {
          'app': 'flutter_identification_mobile',
          'api_base_url': baseUrl,
        },
        'logs': logs,
      },
    );

    if (response.statusCode != 201) {
      throw Exception('Falha ao enviar logs mobile: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final count = body['count'];
    if (count is num) {
      return count.toInt();
    }

    return logs.length;
  }

  Future<http.Response> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final candidates = _candidateBaseUrls();
    Object? lastError;

    for (final candidate in candidates) {
      try {
        return await http
            .post(
              Uri.parse('$candidate$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);
      } on SocketException catch (e) {
        lastError = e;
        continue;
      } on TimeoutException catch (e) {
        lastError = e;
        continue;
      } on http.ClientException catch (e) {
        lastError = e;
        continue;
      }
    }

    if (lastError is TimeoutException) {
      throw Exception(
        'O backend demorou mais de ${_requestTimeout.inSeconds}s para responder em ${_candidateBaseUrls().join(' ou ')}.',
      );
    }

    if (lastError != null) {
      throw Exception('${_networkHint()} Detalhe: $lastError');
    }

    throw Exception(_networkHint());
  }

  Future<http.Response> _get(String path) async {
    final candidates = _candidateBaseUrls();
    Object? lastError;

    for (final candidate in candidates) {
      try {
        return await http
            .get(Uri.parse('$candidate$path'))
            .timeout(_requestTimeout);
      } on SocketException catch (e) {
        lastError = e;
        continue;
      } on TimeoutException catch (e) {
        lastError = e;
        continue;
      } on http.ClientException catch (e) {
        lastError = e;
        continue;
      }
    }

    if (lastError is TimeoutException) {
      throw Exception(
        'O backend demorou mais de ${_requestTimeout.inSeconds}s para responder em ${candidates.join(' ou ')}.',
      );
    }

    if (lastError != null) {
      throw Exception('${_networkHint()} Detalhe: $lastError');
    }

    throw Exception(_networkHint());
  }

  List<String> _candidateBaseUrls() {
    final candidates = <String>[baseUrl];
    if (fallbackBaseUrl != null &&
        fallbackBaseUrl!.isNotEmpty &&
        fallbackBaseUrl != baseUrl) {
      candidates.add(fallbackBaseUrl!);
    }
    return candidates;
  }

  String _networkHint() {
    final candidates = _candidateBaseUrls();
    if (baseUrl.contains('10.0.2.2')) {
      return 'Não foi possível conectar ao backend em ${candidates.join(' ou ')}. '
          'Esse endereço funciona no emulador Android, mas não no celular físico. '
          'Rode o app com --dart-define=API_BASE_URL=http://IP_DA_SUA_MAQUINA:8000.';
    }

    if (baseUrl.contains('127.0.0.1')) {
      return 'Não foi possível conectar ao backend em ${candidates.join(' ou ')}. '
          'Se o app estiver no modo USB, confira se o celular continua conectado e se o adb reverse tcp:8000 tcp:8000 ainda está ativo.';
    }

    if (candidates.any((value) =>
        value.contains('192.168.') ||
        value.contains('10.') ||
        value.contains('172.16.') ||
        value.contains('172.17.') ||
        value.contains('172.18.') ||
        value.contains('172.19.') ||
        value.contains('172.20.') ||
        value.contains('172.21.') ||
        value.contains('172.22.') ||
        value.contains('172.23.') ||
        value.contains('172.24.') ||
        value.contains('172.25.') ||
        value.contains('172.26.') ||
        value.contains('172.27.') ||
        value.contains('172.28.') ||
        value.contains('172.29.') ||
        value.contains('172.30.') ||
        value.contains('172.31.'))) {
      return 'Não foi possível conectar ao backend em ${candidates.join(' ou ')}. '
          'Confira se o Laravel está rodando em 0.0.0.0:8000, '
          'se o celular e o PC estão na mesma rede e se o firewall do Windows liberou a porta 8000.';
    }

    return 'Não foi possível conectar ao backend em ${candidates.join(' ou ')}.';
  }
}
