import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../models/patient_model.dart';
import '../services/api_service.dart';
import '../services/cpf_formatter.dart';
import '../services/embedding_service.dart';
import '../services/face_detector_service.dart';
import '../services/face_image_service.dart';
import 'app_services_provider.dart';
import 'debug_log_provider.dart';

const double _maxAbsYaw = 12.0;
const double _maxAbsRoll = 8.0;
const double _maxAbsPitch = 12.0;
const double _minEyeOpenProbability = 0.35;
const double _identifyThreshold = 0.30;
const double _identifyMinGap = 0.04;

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
    this.errorMessage,
    List<String>? logs,
  }) : logs = logs ?? const [];

  final IdentificationStatus status;
  final PatientModel? patient;
  final String? faceImageB64;
  final String? errorMessage;
  final List<String> logs;

  IdentificationState copyWith({
    IdentificationStatus? status,
    PatientModel? patient,
    String? faceImageB64,
    String? errorMessage,
    List<String>? logs,
    bool clearPatient = false,
    bool clearFaceImageB64 = false,
    bool clearLogs = false,
  }) {
    return IdentificationState(
      status: status ?? this.status,
      patient: clearPatient ? null : (patient ?? this.patient),
      faceImageB64:
          clearFaceImageB64 ? null : (faceImageB64 ?? this.faceImageB64),
      errorMessage: errorMessage,
      logs: clearLogs ? const [] : (logs ?? this.logs),
    );
  }
}

final identificationProvider =
    StateNotifierProvider<IdentificationNotifier, IdentificationState>((ref) {
  return IdentificationNotifier(
    apiService: ref.watch(apiServiceProvider),
    embeddingService: ref.watch(embeddingServiceProvider),
    faceImageService: ref.watch(faceImageServiceProvider),
    faceDetectorService: ref.watch(faceDetectorServiceProvider),
    debugLogController: ref.watch(debugLogControllerProvider.notifier),
  );
});

class IdentificationNotifier extends StateNotifier<IdentificationState> {
  IdentificationNotifier({
    required ApiService apiService,
    required EmbeddingService embeddingService,
    required FaceImageService faceImageService,
    required FaceDetectorService faceDetectorService,
    required DebugLogController debugLogController,
  })  : _apiService = apiService,
        _embeddingService = embeddingService,
        _faceImageService = faceImageService,
        _faceDetectorService = faceDetectorService,
        _debugLogController = debugLogController,
        super(IdentificationState());

  final ApiService _apiService;
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
      _appendLog(
          'Embedding extraido. Baixando pacientes para comparacao local...');
      final patients = await _apiService.fetchPatients();
      final rankedMatches = _rankPatientsByDistance(probeEmbedding, patients);
      final bestMatch = rankedMatches.isEmpty ? null : rankedMatches.first;
      final secondMatch = rankedMatches.length > 1 ? rankedMatches[1] : null;

      if (bestMatch == null || bestMatch.distance > _identifyThreshold) {
        _appendLog('Nenhum paciente ficou dentro do threshold local.');
        state = state.copyWith(
          status: IdentificationStatus.notRecognized,
          faceImageB64: prepared.faceImageB64,
          clearPatient: true,
        );
        return IdentificationStatus.notRecognized;
      }

      if (secondMatch != null &&
          (secondMatch.distance - bestMatch.distance) < _identifyMinGap) {
        _appendLog(
          'Reconhecimento ambíguo: os dois melhores pacientes ficaram muito próximos.',
        );
        state = state.copyWith(
          status: IdentificationStatus.notRecognized,
          faceImageB64: prepared.faceImageB64,
          clearPatient: true,
        );
        return IdentificationStatus.notRecognized;
      }

      _appendLog(
        'Paciente reconhecido localmente: ${bestMatch.patient.name} '
        '(${formatCpfDigits(bestMatch.patient.cpf)}) com distância '
        '${bestMatch.distance.toStringAsFixed(4)}.',
      );
      state = state.copyWith(
        status: IdentificationStatus.recognized,
        patient: bestMatch.patient,
        faceImageB64: prepared.faceImageB64,
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

  Future<bool> registerByCpf(String cpf) async {
    try {
      _appendLog('Cadastrando dados básicos do paciente...');
      state = state.copyWith(
        status: IdentificationStatus.processing,
        errorMessage: null,
      );
      final patient = await _apiService.registerBasicPatient(
        cpf: cpf,
      );

      _appendLog(
        'Paciente criado com ID ${patient.id}. Iniciando cadastro facial guiado.',
      );
      state = state.copyWith(
        status: IdentificationStatus.registered,
        patient: patient,
      );
      return true;
    } catch (e) {
      _appendLog('Erro no cadastro basico: $e');
      state = state.copyWith(
        status: IdentificationStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> registerFaceSampleFromImagePath({
    required int patientId,
    required String captureType,
    required String imagePath,
  }) async {
    try {
      _appendLog('Captura "$captureType" recebida: $imagePath');
      state = state.copyWith(
        status: IdentificationStatus.processing,
        errorMessage: null,
      );

      final prepared = await _prepareFaceCapture(
        imagePath,
        mode: _CaptureMode.enrollment,
      );
      _appendLog(
          'Amostra "$captureType" pronta. Extraindo embedding no APK...');
      final faceEmbedding =
          await _embeddingService.extractEmbedding(prepared.croppedFace);
      _appendLog('Enviando amostra facial "$captureType"...');

      final patient = await _apiService.registerFaceSample(
        patientId: patientId,
        captureType: captureType,
        faceImageB64: prepared.faceImageB64,
        faceEmbedding: faceEmbedding,
      );

      _appendLog(
        'Amostra "$captureType" cadastrada com sucesso. '
        'Total atual: ${patient.faceSamplesCount}.',
      );
      state = state.copyWith(
        status: IdentificationStatus.registered,
        patient: patient,
        faceImageB64: prepared.faceImageB64,
      );
      return true;
    } catch (e) {
      _appendLog('Erro ao cadastrar amostra "$captureType": $e');
      state = state.copyWith(
        status: IdentificationStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
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

  List<_RankedPatientMatch> _rankPatientsByDistance(
    List<double> probeEmbedding,
    List<PatientModel> patients,
  ) {
    final ranked = <_RankedPatientMatch>[];

    for (final patient in patients) {
      double? bestDistance;

      for (final embedding in patient.faceEmbeddings) {
        if (embedding.length != probeEmbedding.length) {
          continue;
        }

        final distance = _cosineDistance(probeEmbedding, embedding);
        if (bestDistance == null || distance < bestDistance) {
          bestDistance = distance;
        }
      }

      if (bestDistance == null) {
        continue;
      }

      ranked.add(_RankedPatientMatch(patient: patient, distance: bestDistance));
    }

    ranked.sort((left, right) => left.distance.compareTo(right.distance));
    return ranked;
  }

  double _cosineDistance(List<double> left, List<double> right) {
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;

    for (var index = 0; index < left.length; index++) {
      final leftValue = left[index];
      final rightValue = right[index];

      dot += leftValue * rightValue;
      leftNorm += leftValue * leftValue;
      rightNorm += rightValue * rightValue;
    }

    if (leftNorm <= 0.0 || rightNorm <= 0.0) {
      return 1.0;
    }

    return 1.0 - (dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm)));
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

class _RankedPatientMatch {
  const _RankedPatientMatch({
    required this.patient,
    required this.distance,
  });

  final PatientModel patient;
  final double distance;
}
