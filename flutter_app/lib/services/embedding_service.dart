import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class EmbeddingService {
  static const MethodChannel _channel = MethodChannel(
    'afericao_automatizada_mobile/deepface',
  );
  static const String _defaultModelName = 'Facenet512';
  Future<void>? _warmupFuture;

  Future<void> warmup() {
    return _warmupFuture ??= _performWarmup();
  }

  Future<void> _performWarmup() async {
    try {
      await _channel.invokeMethod<bool>(
        'warmup',
        <String, dynamic>{'modelName': _defaultModelName},
      );
    } on PlatformException catch (error) {
      final details = error.details?.toString();
      throw Exception(
        'Falha ao aquecer DeepFace nativo '
        '[${error.code}]: ${error.message ?? 'sem mensagem'}'
        '${details == null || details.isEmpty ? '' : '\n$details'}',
      );
    }
  }

  Future<List<double>> extractEmbedding(img.Image image) async {
    await warmup();
    final imageBytes = img.encodeJpg(image, quality: 95);
    List<dynamic>? response;

    try {
      response = await _channel.invokeListMethod<dynamic>(
        'extractEmbedding',
        <String, dynamic>{
          'imageBytes': imageBytes,
          'modelName': _defaultModelName,
        },
      );
    } on PlatformException catch (error) {
      final details = error.details?.toString();
      throw Exception(
        'Falha no DeepFace nativo '
        '[${error.code}]: ${error.message ?? 'sem mensagem'}'
        '${details == null || details.isEmpty ? '' : '\n$details'}',
      );
    }

    if (response == null || response.isEmpty) {
      throw Exception('O DeepFace retornou um embedding vazio.');
    }

    return response
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList(growable: false);
  }

  Future<void> close() async {}
}
