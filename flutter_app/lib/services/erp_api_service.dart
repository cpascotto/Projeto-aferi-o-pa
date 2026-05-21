import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/patient_model.dart';

class ErpApiService {
  ErpApiService({
    required this.baseUrl,
    this.fallbackBaseUrl,
    this.afericaoUrl,
  });

  static const Duration _requestTimeout = Duration(seconds: 20);

  final String baseUrl;
  final String? fallbackBaseUrl;
  final String? afericaoUrl;

  Future<ErpResponse> validateBiometric({
    required String unitId,
    required String deviceId,
    required DateTime recognizedAt,
    int? patientId,
    List<double>? faceEmbedding,
    String? faceImageB64,
  }) {
    final biometria = _encodeBiometria(faceEmbedding, faceImageB64);
    return _sendAction({
      'ID_Unidade': unitId,
      'TMS_Reconhecimento': _formatDateTime(recognizedAt),
      if (patientId != null) 'ID_Cliente': patientId.toString(),
      if (biometria.isNotEmpty) 'Biometria_Facial': biometria,
      'Acao': 'N1',
    });
  }

  Future<ErpResponse> validateCpf({
    required String unitId,
    required String deviceId,
    required DateTime recognizedAt,
    required String cpf,
    List<double>? faceEmbedding,
    String? faceImageB64,
  }) {
    final biometria = _encodeBiometria(faceEmbedding, faceImageB64);
    return _sendAction({
      'ID_Unidade': unitId,
      'TMS_Reconhecimento': _formatDateTime(recognizedAt),
      if (biometria.isNotEmpty) 'Biometria_Facial': biometria,
      'CPF': cpf,
      'Acao': 'N2',
    });
  }

  Future<ErpResponse> registerMeasurement({
    required String deviceId,
    required int clientId,
    required int contractId,
    String? nextInteractionAt,
    required int systolic,
    required int diastolic,
    required int bpm,
    String? rawPayload,
  }) {
    return _sendAction({
      'ID_Cliente': clientId.toString(),
      'ID_Acordo': contractId.toString(),
      'TMS_Proxima_interacao': nextInteractionAt ?? '',
      'Sistolica': systolic,
      'Diastolica': diastolic,
      'BPM': bpm,
      'Acao': 'N3',
    });
  }

  Future<ErpResponse> registerRefusal({
    required String deviceId,
    required int clientId,
    required int contractId,
    String? nextInteractionAt,
  }) {
    return _sendAction({
      'ID_Cliente': clientId.toString(),
      'ID_Acordo': contractId.toString(),
      'TMS_Proxima_interacao': nextInteractionAt ?? '',
      'Acao': 'N4',
    });
  }

  Future<ErpResponse> finalizeSession({
    required String deviceId,
    required int clientId,
    required int contractId,
    String? nextInteractionAt,
  }) {
    return _sendAction({
      'ID_Cliente': clientId.toString(),
      'ID_Acordo': contractId.toString(),
      if (nextInteractionAt != null) 'TMS_Proxima_interacao': nextInteractionAt,
      'Acao': 'F1',
    });
  }

  Future<ErpResponse> _sendAction(Map<String, dynamic> body) async {
    final response = await _postJson({
      'sdtAfericao01Ent': body,
    });
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(decoded) ?? response.body);
    }

    return ErpResponse.fromJson(decoded);
  }

  Future<http.Response> _postJson(Map<String, dynamic> body) async {
    final candidates = _candidateActionUrls();
    Object? lastError;

    for (final candidate in candidates) {
      try {
        return await http
            .post(
              Uri.parse(candidate),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);
      } on SocketException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }

    if (lastError is TimeoutException) {
      throw Exception(
        'O ERP demorou mais de ${_requestTimeout.inSeconds}s para responder em ${candidates.join(' ou ')}.',
      );
    }

    if (lastError != null) {
      throw Exception(
        'Nao foi possivel conectar ao ERP em ${candidates.join(' ou ')}. Detalhe: $lastError',
      );
    }

    throw Exception(
      'Nao foi possivel conectar ao ERP em ${candidates.join(' ou ')}.',
    );
  }

  String _encodeBiometria(List<double>? embedding, String? imageB64) {
    if (embedding != null && embedding.isNotEmpty) {
      return jsonEncode(embedding);
    }
    return imageB64 ?? '';
  }

  /// Formata DateTime para o padrão esperado pelo Forza: "yyyy-MM-dd HH:mm:ss"
  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }

  String? _extractError(Map<String, dynamic> json) {
    final wrapped = json['sdtAfericao01Sai'];
    if (wrapped is Map<String, dynamic>) {
      final messages = wrapped['Mensagem'];
      if (messages is List && messages.isNotEmpty) {
        final first = messages.first;
        if (first is Map && first['Msg'] != null) {
          return first['Msg'].toString();
        }
      }
    }

    return json['error']?.toString() ?? json['message']?.toString();
  }

  List<String> _candidateActionUrls() {
    final url = afericaoUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return [url];
    }

    return _candidateBaseUrls()
        .map((candidate) => '$candidate/api/erp/action')
        .toList(growable: false);
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
}

class ErpResponse {
  const ErpResponse({
    required this.message,
    this.action,
    this.clientId,
    this.clientName,
    this.cpf,
    this.contractId,
    this.attendanceId,
    this.measurementId,
    this.outOfRange = false,
    this.nextInterventionAt,
    this.nextInteractionAt,
    this.preferredName,
    this.patient,
    this.raw,
  });

  factory ErpResponse.fromJson(Map<String, dynamic> json) {
    final wrapped = json['sdtAfericao01Sai'];
    if (wrapped is Map<String, dynamic>) {
      return ErpResponse._fromForzaJson(wrapped, raw: json);
    }
    return ErpResponse._fromLegacyJson(json);
  }

  factory ErpResponse._fromForzaJson(
    Map<String, dynamic> json, {
    required Map<String, dynamic> raw,
  }) {
    final message = _firstMessage(json['Mensagem']);
    final nextInteractionAt = _firstText(
      json,
      const [
        'TMS_Proxima_interacao',
        'TMS_Proxima_interação',
        'TMS_Proxima_Intervencao',
        'TMS_Proxima_Intervenção',
      ],
    );
    return ErpResponse(
      message: message.code,
      action: null,
      clientId: _parseInt(json['ID_Cliente']),
      clientName: json['Nome_Cliente']?.toString(),
      cpf: _firstText(json, const ['CPF']),
      contractId: _parseInt(json['ID_Acordo']),
      outOfRange: message.code == 7 ||
          message.code == 14 ||
          message.code == 15 ||
          message.code == 16,
      nextInterventionAt: _parseDate(nextInteractionAt),
      nextInteractionAt: nextInteractionAt,
      preferredName: _firstText(json, const ['Nome_Pref', 'Nome_Preferido']),
      raw: raw,
    );
  }

  factory ErpResponse._fromLegacyJson(Map<String, dynamic> json) {
    final patientJson = json['patient'];
    return ErpResponse(
      message: _parseInt(json['message']) ?? 0,
      action: json['action']?.toString(),
      clientId: _parseInt(json['client_id']),
      clientName: json['client_name']?.toString(),
      contractId: _parseInt(json['contract_id']),
      attendanceId: _parseInt(json['attendance_id']),
      measurementId: _parseInt(json['measurement_id']),
      outOfRange: json['out_of_range'] == true,
      nextInterventionAt: _parseDate(json['next_intervention_at']),
      nextInteractionAt: json['next_interaction_at']?.toString() ??
          json['next_intervention_at']?.toString(),
      preferredName: json['preferred_name']?.toString(),
      patient: patientJson is Map<String, dynamic>
          ? PatientModel.fromJson(patientJson)
          : null,
      raw: json,
    );
  }

  final int message;
  final String? action;
  final int? clientId;
  final String? clientName;
  final String? cpf;
  final int? contractId;
  final int? attendanceId;
  final int? measurementId;
  final bool outOfRange;
  final DateTime? nextInterventionAt;
  final String? nextInteractionAt;
  final String? preferredName;
  final PatientModel? patient;
  final Map<String, dynamic>? raw;

  static _ForzaMessage _firstMessage(Object? value) {
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) {
        return _ForzaMessage(
          code: _parseInt(first['Cod']) ?? 0,
        );
      }
    }

    return const _ForzaMessage(code: 0);
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _firstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}

class _ForzaMessage {
  const _ForzaMessage({
    required this.code,
  });

  final int code;
}
