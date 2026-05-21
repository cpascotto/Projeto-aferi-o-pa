import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/embedding_service.dart';
import '../services/equipment_settings_service.dart';
import '../services/erp_api_service.dart';
import '../services/face_detector_service.dart';
import '../services/face_image_service.dart';

// A API local (Laravel) foi descontinuada — o app usa apenas o ERP.
// Mantemos os campos vazios por compatibilidade com a ApiService legacy
// (cujas chamadas falham graciosamente quando baseUrl é vazio).
const String apiBaseUrlFromEnv = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);
const String fallbackApiBaseUrlFromEnv = String.fromEnvironment(
  'API_FALLBACK_BASE_URL',
  defaultValue: '',
);
const String defaultErpAfericaoUrl =
    'https://api.forzauno.com.br/KB16WT/rest/Forza/prcAfericao01';
const String erpAfericaoUrlFromEnv = String.fromEnvironment(
  'ERP_AFERICAO_URL',
  defaultValue: defaultErpAfericaoUrl,
);

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(
    baseUrl: apiBaseUrlFromEnv,
    fallbackBaseUrl: fallbackApiBaseUrlFromEnv,
  );
});

final erpApiServiceProvider = Provider<ErpApiService>((ref) {
  return ErpApiService(
    baseUrl: apiBaseUrlFromEnv,
    fallbackBaseUrl: fallbackApiBaseUrlFromEnv,
    afericaoUrl: erpAfericaoUrlFromEnv,
  );
});

final equipmentSettingsServiceProvider =
    Provider<EquipmentSettingsService>((ref) {
  return EquipmentSettingsService();
});

final faceImageServiceProvider = Provider<FaceImageService>((ref) {
  return FaceImageService();
});

final faceDetectorServiceProvider = Provider<FaceDetectorService>((ref) {
  final service = FaceDetectorService();
  ref.onDispose(() {
    service.close();
  });
  return service;
});

final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  final service = EmbeddingService();
  ref.onDispose(() {
    service.close();
  });
  return service;
});
