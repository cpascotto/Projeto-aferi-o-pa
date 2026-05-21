import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../models/patient_model.dart';
import '../services/embedding_service.dart';
import '../services/face_detector_service.dart';
import '../services/face_image_service.dart';
import 'app_services_provider.dart';
import 'debug_log_provider.dart';

const double _maxAbsYaw = 12.0;
const double _maxAbsRoll = 8.0;
const double _maxAbsPitch = 12.0;
const double _minEyeOpenProbability = 0.35;

enum IdentificationStatus {
  idle,
  processing,
  recognized,
  notRecognized,
  registered,
  error,
}

class IdentificationState {
  IdentificationState({
    this.status = IdentificationStatus.idle,
    this.patient,
    this.faceImageB64,
    this.faceEmbedding,
    this.errorMessage,
    this.contractId,
    this.deviceId,
    this.nextInteractionAt,
    List<String>? logs,
  }) : logs = logs ?? const [];

  final IdentificationStatus status;
  final PatientModel? patient;
  final String? faceImageB64;
  final List<double>? faceEmbedding;
  final String? errorMessage;
  final int? contractId;
  final String? deviceId;
  final String? nextInteractionAt;
  final List<String> logs;

  IdentificationState copyWith({
    IdentificationStatus? status,
    PatientModel? patient,
    String? faceImageB64,
    List<double>? faceEmbedding,
    String? errorMessage,
    int? contractId,
    String? deviceId,
    String? nextInteractionAt,
    List<String>? logs,
    bool clearPatient = false,
    bool clearFaceImageB64 = false,
    bool clearFaceEmbedding = false,
    bool clearLogs = false,
  }) {
    return IdentificationState(
      status: status ?? this.status,
      patient: clearPatient ? null : (patient ?? this.patient),
      faceImageB64:
          clearFaceImageB64 ? null : (faceImageB64 ?? this.faceImageB64),
      faceEmbedding:
          clearFaceEmbedding ? null : (faceEmbedding ?? this.faceEmbedding),
      errorMessage: errorMessage,
      contractId: contractId ?? this.contractId,
      deviceId: deviceId ?? this.deviceId,
      nextInteractionAt: nextInteractionAt ?? this.nextInteractionAt,
      logs: clearLogs ? const [] : (logs ?? this.logs),
    );
  }
}

final identificationProvider =
    StateNotifierProvider<IdentificationNotifier, IdentificationState>((ref) {
  return IdentificationNotifier(
    embeddingService: ref.watch(embeddingServiceProvider),
    faceImageService: ref.watch(faceImageServiceProvider),
    faceDetectorService: ref.watch(faceDetectorServiceProvider),
    debugLogController: ref.watch(debugLogControllerProvider.notifier),
  );
});

class IdentificationNotifier extends StateNotifier<IdentificationState> {
  IdentificationNotifier({
    required EmbeddingService embeddingService,
    required FaceImageService faceImageService,
    required FaceDetectorService faceDetectorService,
    required DebugLogController debugLogController,
  })  : _embeddingService = embeddingService,
        _faceImageService = faceImageService,
        _faceDetectorService = faceDetectorService,
        _debugLogController = debugLogController,
        super(IdentificationState());

  final EmbeddingService _embeddingService;
  final FaceImageService _faceImageService;
  final FaceDetectorService _faceDetectorService;
  final DebugLogController _debugLogController;

  void startAttempt() {
    state = IdentificationState(
      status: IdentificationStatus.idle,
      logs: const [],
    );
    _appendLog('Nova tentativa iniciada.');
  }

  Future<IdentificationStatus> identifyFromImagePath(String imagePath) async {
    try {
      _appendLog('Recebi a imagem capturada: $imagePath');
      state = state.copyWith(
        status: IdentificationStatus.processing,
        errorMessage: null,
      );

      final prepared = await _prepareFaceCapture(
        imagePath,
        mode: _CaptureMode.identification,
      );
      _appendLog('Face preparada localmente. Extraindo embedding no APK...');
      final probeEmbedding =
          await _embeddingService.extractEmbedding(prepared.croppedFace);
      _appendLog('Embedding extraido. Validando biometria no ERP...');

      // Não limpa o patient — preserva dados ERP (clientId, contractId)
      // que podem ter sido salvos por setErpData antes desta chamada.
      state = state.copyWith(
        status: IdentificationStatus.recognized,
        faceImageB64: prepared.faceImageB64,
        faceEmbedding: probeEmbedding,
      );
      return IdentificationStatus.recognized;
    } catch (e) {
      _appendLog('Erro na identificação: $e');
      state = state.copyWith(
        status: IdentificationStatus.error,
        errorMessage: e.toString(),
      );
      return IdentificationStatus.error;
    }
  }

  /// Armazena os dados do paciente vindos de uma resposta ERP (N2)
  /// para que as telas seguintes possam acessar contractId, deviceId, etc.
  void setErpData({
    required PatientModel patient,
    required int contractId,
    required String deviceId,
    String? nextInteractionAt,
  }) {
    state = state.copyWith(
      patient: patient,
      contractId: contractId,
      deviceId: deviceId,
      nextInteractionAt: nextInteractionAt,
    );
  }

  void reset() {
    state = IdentificationState();
  }

  Future<_PreparedFaceCapture> _prepareFaceCapture(
    String imagePath, {
    required _CaptureMode mode,
  }) async {
    _appendLog('Detectando rosto na foto capturada...');
    final normalizedImage =
        await _faceImageService.loadNormalizedImage(imagePath);
    final detectedFace =
        await _faceDetectorService.detectPrimaryFaceFromFile(imagePath);

    if (detectedFace == null) {
      throw Exception('Nenhum rosto foi detectado na foto capturada.');
    }
    _appendLog(
      'Rosto detectado em x=${detectedFace.boundingBox.left.toStringAsFixed(1)}, '
      'y=${detectedFace.boundingBox.top.toStringAsFixed(1)}, '
      'w=${detectedFace.boundingBox.width.toStringAsFixed(1)}, '
      'h=${detectedFace.boundingBox.height.toStringAsFixed(1)}.',
    );
    _appendLog(
      'Landmarks: '
      'olhoE=${detectedFace.leftEye != null ? 'ok' : 'não'} '
      'olhoD=${detectedFace.rightEye != null ? 'ok' : 'não'} '
      'nariz=${detectedFace.noseBase != null ? 'ok' : 'não'} '
      'contorno=${detectedFace.faceContour.isNotEmpty ? 'ok' : 'não'}.',
    );
    _appendLog(
      'Angulos/Eyes: '
      'pitch=${(detectedFace.headEulerAngleX ?? 0).toStringAsFixed(1)} '
      'yaw=${(detectedFace.headEulerAngleY ?? 0).toStringAsFixed(1)} '
      'roll=${(detectedFace.headEulerAngleZ ?? 0).toStringAsFixed(1)} '
      'eyeL=${(detectedFace.leftEyeOpenProbability ?? -1).toStringAsFixed(2)} '
      'eyeR=${(detectedFace.rightEyeOpenProbability ?? -1).toStringAsFixed(2)}.',
    );
    if (detectedFace.leftEye == null ||
        detectedFace.rightEye == null ||
        detectedFace.noseBase == null ||
        (detectedFace.mouthBottom == null &&
            (detectedFace.mouthLeft == null ||
                detectedFace.mouthRight == null)) ||
        detectedFace.faceContour.length < 24) {
      throw Exception(
        'A captura facial ficou incompleta ou parcialmente obstruida. '
        'Mantenha olhos, nariz e boca totalmente visíveis dentro do círculo.',
      );
    }
    _validateDetectedFaceQuality(detectedFace, mode: mode);

    final faceCrop = _faceImageService.cropFaceFromDetectedFace(
      normalizedImage,
      detectedFace,
    );
    final croppedFace = faceCrop.image;
    _appendLog(
      'Face recortada para ${croppedFace.width}x${croppedFace.height} antes do embedding.',
    );
    _appendLog(
      'Crop final em x=${faceCrop.cropRect.left.toStringAsFixed(1)}, '
      'y=${faceCrop.cropRect.top.toStringAsFixed(1)}, '
      'lado=${faceCrop.cropRect.width.toStringAsFixed(1)}.',
    );
    final faceImageB64 = _faceImageService.imageToBase64(croppedFace);

    return _PreparedFaceCapture(
      croppedFace: croppedFace,
      faceImageB64: faceImageB64,
    );
  }

  void _validateDetectedFaceQuality(
    DetectedFace detectedFace, {
    required _CaptureMode mode,
  }) {
    final yaw = (detectedFace.headEulerAngleY ?? 0).abs();
    final roll = (detectedFace.headEulerAngleZ ?? 0).abs();
    final pitch = (detectedFace.headEulerAngleX ?? 0).abs();
    if (yaw > _maxAbsYaw || roll > _maxAbsRoll || pitch > _maxAbsPitch) {
      throw Exception(
        mode == _CaptureMode.enrollment
            ? 'Rosto fora de frontalidade. Olhe diretamente para a câmera, com a cabeça reta.'
            : 'Rosto fora de frontalidade. Tente novamente olhando de frente para a câmera.',
      );
    }

    final leftEye = detectedFace.leftEyeOpenProbability;
    final rightEye = detectedFace.rightEyeOpenProbability;
    if ((leftEye != null && leftEye < _minEyeOpenProbability) ||
        (rightEye != null && rightEye < _minEyeOpenProbability)) {
      throw Exception(
        'Os olhos não ficaram visíveis o suficiente para reconhecimento confiável.',
      );
    }
  }

  void _appendLog(String message) {
    unawaited(
      _debugLogController.recordLog(
        message,
        source: 'identification',
      ),
    );
    state = state.copyWith(
      logs: [...state.logs, _stamp(message)],
    );
  }

  String _stamp(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '[$hh:$mm:$ss] $message';
  }

}

class _PreparedFaceCapture {
  const _PreparedFaceCapture({
    required this.croppedFace,
    required this.faceImageB64,
  });

  final img.Image croppedFace;
  final String faceImageB64;
}

enum _CaptureMode {
  identification,
  enrollment,
}
