import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/embedding_service.dart';
import '../services/face_detector_service.dart';
import '../services/face_image_service.dart';

const String defaultApiBaseUrl = 'http://127.0.0.1:8000';
const String apiBaseUrlFromEnv = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: defaultApiBaseUrl,
);
const String fallbackApiBaseUrlFromEnv = String.fromEnvironment(
  'API_FALLBACK_BASE_URL',
  defaultValue: defaultApiBaseUrl,
);

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(
    baseUrl: apiBaseUrlFromEnv,
    fallbackBaseUrl: fallbackApiBaseUrlFromEnv,
  );
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
