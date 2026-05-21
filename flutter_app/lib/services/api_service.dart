import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
  static const Duration _requestTimeout = Duration(seconds: 20);

  ApiService({
    required this.baseUrl,
    this.fallbackBaseUrl,
  });

  final String baseUrl;
  final String? fallbackBaseUrl;

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
