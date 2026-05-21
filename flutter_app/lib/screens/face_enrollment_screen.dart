import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_services_provider.dart';
import '../providers/debug_log_provider.dart';
import '../providers/identification_provider.dart';
import '../services/face_detector_service.dart';
import '../widgets/totem_back_button.dart';
import 'identification_screen.dart';

class FaceEnrollmentScreen extends ConsumerStatefulWidget {
  const FaceEnrollmentScreen({super.key});

  @override
  ConsumerState<FaceEnrollmentScreen> createState() =>
      _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends ConsumerState<FaceEnrollmentScreen> {
  static const Duration _captureHoldDuration = Duration(seconds: 3);
  // Dispara a foto no meio da contagem para que, no final, ela já esteja pronta.
  static const Duration _earlyCaptureAt = Duration(milliseconds: 1500);
  static const double _guideCenterX = 0.5;
  static const double _guideCenterY = 0.50;
  static const double _guideRadius = 0.28;
  static const double _guideRadiusTolerance = 1.45;
  static const double _minFaceWidth = 0.20;
  static const double _minFaceHeight = 0.24;
  static const double _minFaceArea = 0.052;
  static const double _maxFaceSize = 0.72;
  static const double _bottomPanelHeight = 135;
  static const double _logoHeaderHeight = 92;

  CameraController? _controller;
  CameraDescription? _selectedCamera;
  late FaceDetectorService _faceDetectorService;
  Timer? _countdownTimer;
  Timer? _earlyCaptureTimer;

  bool _processingFrame = false;
  bool _hasCaptured = false;
  bool _captureStarted = false;
  bool _captureFinalized = false;
  bool _isStreaming = false;
  bool _isInitializing = true;
  bool _showIntro = true;
  bool _showSuccess = false;
  bool _isLeaving = false;

  String? _cameraError;
  String? _capturedImagePath;
  String _statusText = 'Inicializando câmera...';

  DateTime? _faceCenteredSince;
  int _countdownSeconds = _captureHoldDuration.inSeconds;
  _EnrollmentVisualState _visualState = _EnrollmentVisualState.guide;

  @override
  void initState() {
    super.initState();
    _faceDetectorService = FaceDetectorService();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializing = true;
      _cameraError = null;
      _showIntro = false;
      _statusText = 'Inicializando câmera...';
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('Nenhuma câmera encontrada.');
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = kIsWeb
          ? CameraController(
              frontCamera,
              ResolutionPreset.medium,
              enableAudio: false,
            )
          : CameraController(
              frontCamera,
              ResolutionPreset.medium,
              enableAudio: false,
              imageFormatGroup: ImageFormatGroup.nv21,
            );

      await controller.initialize();

      _controller?.dispose();
      _controller = controller;
      _selectedCamera = frontCamera;

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });

      await _startEnrollment();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _cameraError = error.toString();
        _statusText = 'Falha ao acessar câmera.';
      });
    }
  }

  Future<void> _startEnrollment() async {
    final controller = _controller;
    final selectedCamera = _selectedCamera;

    if (controller == null ||
        !controller.value.isInitialized ||
        selectedCamera == null) {
      if (!mounted) return;
      setState(() {
        _statusText = 'Câmera indisponível. Tente novamente.';
      });
      return;
    }

    if (_isStreaming) return;

    _cancelCaptureTimers();
    if (!mounted) return;
    setState(() {
      _hasCaptured = false;
      _captureStarted = false;
      _captureFinalized = false;
      _capturedImagePath = null;
      _faceCenteredSince = null;
      _countdownSeconds = _captureHoldDuration.inSeconds;
      _visualState = _EnrollmentVisualState.guide;
      _statusText = 'Centralize o rosto no círculo.';
    });

    await controller.startImageStream((image) {
      _onFrame(image, selectedCamera);
    });

    if (!mounted) return;
    setState(() {
      _isStreaming = true;
    });
  }

  Future<void> _stopEnrollmentStream() async {
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }

    if (!mounted) return;
    setState(() {
      _isStreaming = false;
    });
  }

  Future<void> _onFrame(CameraImage image, CameraDescription camera) async {
    if (_processingFrame || _hasCaptured || _controller == null) return;

    _processingFrame = true;
    try {
      final faceRect = await _faceDetectorService.detectPrimaryFaceNormalized(
        image,
        camera,
        _controller!.value.deviceOrientation,
      );

      if (_hasCaptured) return;

      if (faceRect == null) {
        _resetCaptureHold(
          statusText:
              _isStreaming ? 'Centralize o rosto no círculo.' : _statusText,
        );
        return;
      }

      final validationMessage = _validateFaceForCapture(faceRect);
      final now = DateTime.now();

      if (validationMessage != null) {
        _resetCaptureHold(statusText: validationMessage);
        return;
      }

      if (_faceCenteredSince == null) {
        _startCaptureHold(now);
      }
      final elapsed = now.difference(_faceCenteredSince!);
      _updateCountdownUi(elapsed);

      if (elapsed >= _earlyCaptureAt && !_captureStarted) {
        await _captureFaceSample(fromValidatedFrame: true);
      }

      if (elapsed >= _captureHoldDuration) {
        await _finishCaptureHold();
      }
    } catch (error) {
      await _recoverFromCaptureError(error);
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _captureFaceSample({bool fromValidatedFrame = false}) async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _captureStarted ||
        _captureFinalized ||
        _faceCenteredSince == null ||
        _isLeaving) {
      return;
    }

    if (_processingFrame && !fromValidatedFrame) {
      _earlyCaptureTimer?.cancel();
      _earlyCaptureTimer = Timer(
        const Duration(milliseconds: 120),
        () => unawaited(_captureFaceSample()),
      );
      return;
    }

    _captureStarted = true;
    _hasCaptured = true;
    _earlyCaptureTimer?.cancel();

    try {
      await _stopEnrollmentStream();
      final picture = await controller.takePicture();
      _capturedImagePath = picture.path;

      if (_isHoldComplete) {
        await _completeCapturedFaceSample(picture.path);
      }
    } catch (error) {
      await _recoverFromCaptureError(error);
    }
  }

  Future<void> _finishCaptureHold() async {
    if (_captureFinalized || _isLeaving) return;

    _countdownTimer?.cancel();

    if (!_captureStarted) {
      await _captureFaceSample();
    }

    final imagePath = _capturedImagePath;
    if (imagePath == null) {
      if (mounted) {
        setState(() {
          _countdownSeconds = 1;
          _statusText = 'Capturando foto...';
        });
      }
      return;
    }

    await _completeCapturedFaceSample(imagePath);
  }

  Future<void> _completeCapturedFaceSample(String imagePath) async {
    if (_captureFinalized || _isLeaving) return;

    _captureFinalized = true;
    _cancelCaptureTimers();

    if (mounted) {
      setState(() {
        _visualState = _EnrollmentVisualState.completed;
        _statusText = 'Processando rosto...';
      });
    }

    // 1) Extrai embedding localmente.
    final status = await ref
        .read(identificationProvider.notifier)
        .identifyFromImagePath(imagePath);

    if (!mounted || _isLeaving) return;

    if (status == IdentificationStatus.error) {
      final errorMsg =
          ref.read(identificationProvider).errorMessage ??
          'Falha ao processar rosto.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
      _captureFinalized = false;
      _resetCaptureHold(
          statusText: 'Falha. Reposicione o rosto e tente novamente.');
      await _startEnrollment();
      return;
    }

    // 2) Registra a biometria no Forza.
    //    Estratégia primária: N1 com ID_Cliente + embedding
    //    (Forza associa o embedding ao cliente para reconhecimento futuro).
    //    Fallback: N2 com CPF + embedding.
    if (mounted) {
      setState(() => _statusText = 'Registrando biometria...');
    }

    final log = ref.read(debugLogControllerProvider.notifier);

    try {
      final idState = ref.read(identificationProvider);
      final equipmentSettings = ref.read(equipmentSettingsServiceProvider);
      final unitId = await equipmentSettings.getUnitId();
      final deviceId = await equipmentSettings.getDeviceId();
      final patientId = idState.patient?.id;
      final cpf = idState.patient?.cpf ?? '';
      final embLen = idState.faceEmbedding?.length ?? 0;

      // Loga os primeiros e últimos 5 valores do embedding para diagnóstico.
      final embPreview = idState.faceEmbedding != null && idState.faceEmbedding!.length >= 10
          ? '${idState.faceEmbedding!.take(5).map((v) => v.toStringAsFixed(4)).join(',')} ... ${idState.faceEmbedding!.skip(idState.faceEmbedding!.length - 5).map((v) => v.toStringAsFixed(4)).join(',')}'
          : '(vazio)';
      unawaited(log.recordLog(
        'ENROLLMENT: patientId=$patientId cpf="${cpf.isEmpty ? "(vazio)" : cpf.substring(0, 3) + "***"}" embeddingLen=$embLen unitId=$unitId\nEMBEDDING_PREVIEW: [$embPreview]',
        source: 'enrollment',
      ));

      // Loga o embedding completo para testes manuais na API Forza.
      if (idState.faceEmbedding != null && idState.faceEmbedding!.isNotEmpty) {
        unawaited(log.recordLog(
          'ENROLLMENT_EMBEDDING_FULL: ${jsonEncode(idState.faceEmbedding)}',
          source: 'enrollment',
        ));
      }

      // Estratégia:
      //   Passo 1 — N2 com CPF + embedding: valida o CPF, obtém clientId e
      //             tenta salvar o embedding no Forza.
      //   Passo 2 — N1 com ID_Cliente + embedding: garante que a biometria
      //             fique persistida no banco do ERP para reconhecimento futuro.
      //             (O Forza só grava no banco quando recebe N1 com o clientId
      //             explícito; o N2 sozinho só persiste na sessão ASP.NET.)
      if (cpf.isNotEmpty) {
        // — Passo 1: N2 com CPF + embedding —
        unawaited(log.recordLog(
          'ENROLLMENT PASSO-1: chamando N2 com CPF + embedding',
          source: 'enrollment',
        ));
        final n2Resp = await ref.read(erpApiServiceProvider).validateCpf(
              unitId: unitId,
              deviceId: deviceId,
              recognizedAt: DateTime.now(),
              cpf: cpf,
              faceEmbedding: idState.faceEmbedding,
            );
        unawaited(log.recordLog(
          'ENROLLMENT N2 RESP: msg=${n2Resp.message} clientId=${n2Resp.clientId} contractId=${n2Resp.contractId}',
          source: 'enrollment',
          context: {'raw': n2Resp.raw?.toString() ?? 'null'},
        ));

        // — Passo 2: N1 com ID_Cliente + embedding para persistir no banco —
        // O Forza grava a biometria permanentemente quando N1 é chamado com
        // ID_Cliente + Biometria_Facial. Sem essa chamada, o embedding fica
        // apenas na sessão ASP.NET do servidor e é perdido entre requisições.
        final enrollClientId = n2Resp.clientId;
        if (enrollClientId != null && idState.faceEmbedding != null && idState.faceEmbedding!.isNotEmpty) {
          unawaited(log.recordLog(
            'ENROLLMENT PASSO-2: chamando N1 com ID_Cliente=$enrollClientId + embedding para persistir biometria no banco Forza',
            source: 'enrollment',
          ));
          try {
            final n1Resp = await ref.read(erpApiServiceProvider).validateBiometric(
                  unitId: unitId,
                  deviceId: deviceId,
                  recognizedAt: DateTime.now(),
                  patientId: enrollClientId,
                  faceEmbedding: idState.faceEmbedding,
                );
            unawaited(log.recordLog(
              'ENROLLMENT N1 PERSIST RESP: msg=${n1Resp.message} clientId=${n1Resp.clientId} contractId=${n1Resp.contractId}',
              source: 'enrollment',
              context: {'raw': n1Resp.raw?.toString() ?? 'null'},
            ));
          } catch (e) {
            unawaited(log.recordLog(
              'ENROLLMENT N1 PERSIST ERRO (nao bloqueia): $e',
              source: 'enrollment',
            ));
          }
        } else {
          unawaited(log.recordLog(
            'ENROLLMENT PASSO-2: pulado — clientId=${enrollClientId ?? "null"} embeddingLen=${idState.faceEmbedding?.length ?? 0}',
            source: 'enrollment',
          ));
        }
      } else if (patientId != null) {
        // Fallback: CPF não disponível — tenta N1 com ID_Cliente diretamente.
        unawaited(log.recordLog(
          'ENROLLMENT: CPF vazio, usando fallback N1 com ID_Cliente=$patientId',
          source: 'enrollment',
        ));
        final resp = await ref.read(erpApiServiceProvider).validateBiometric(
              unitId: unitId,
              deviceId: deviceId,
              recognizedAt: DateTime.now(),
              patientId: patientId,
              faceEmbedding: idState.faceEmbedding,
            );
        unawaited(log.recordLog(
          'ENROLLMENT N1 RESP: msg=${resp.message} clientId=${resp.clientId} contractId=${resp.contractId}',
          source: 'enrollment',
          context: {'raw': resp.raw?.toString() ?? 'null'},
        ));
      } else {
        unawaited(log.recordLog(
          'ENROLLMENT: CPF e patientId ambos vazios — nenhuma chamada feita ao Forza!',
          source: 'enrollment',
        ));
      }
    } catch (e) {
      unawaited(log.recordLog(
        'ENROLLMENT ERROR: $e',
        source: 'enrollment',
      ));
      // Falha ao salvar no Forza — avisa mas não bloqueia o fluxo.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível registrar biometria no servidor. $e',
            ),
          ),
        );
      }
    }

    if (!mounted || _isLeaving) return;

    // 3) Mostra tela de sucesso.
    if (mounted) {
      setState(() => _showSuccess = true);
    }

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || _isLeaving) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const IdentificationScreen()),
    );
  }

  void _startCaptureHold(DateTime startedAt) {
    _faceCenteredSince = startedAt;
    _countdownTimer?.cancel();
    _earlyCaptureTimer?.cancel();
    _countdownTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _updateCountdownFromTimer(),
    );
    _earlyCaptureTimer = Timer(
      _earlyCaptureAt,
      () => unawaited(_captureFaceSample()),
    );
  }

  void _updateCountdownFromTimer() {
    final startedAt = _faceCenteredSince;
    if (startedAt == null || _captureFinalized || _isLeaving) return;

    final elapsed = DateTime.now().difference(startedAt);
    _updateCountdownUi(elapsed);

    if (elapsed >= _captureHoldDuration) {
      _countdownTimer?.cancel();
      unawaited(_finishCaptureHold());
    }
  }

  void _updateCountdownUi(Duration elapsed) {
    if (!mounted || _captureFinalized || _isLeaving) return;

    final remaining = (_captureHoldDuration - elapsed).inMilliseconds;
    final countdown = remaining > 0 ? (remaining / 1000).ceil() : 1;

    setState(() {
      _visualState = _EnrollmentVisualState.countdown;
      _countdownSeconds = countdown.clamp(1, 3);
      _statusText = remaining <= 0 && _capturedImagePath == null
          ? 'Capturando foto...'
          : 'Não se mova, estamos cadastrando seu rosto';
    });
  }

  bool get _isHoldComplete {
    final startedAt = _faceCenteredSince;
    return startedAt != null &&
        DateTime.now().difference(startedAt) >= _captureHoldDuration;
  }

  void _resetCaptureHold({required String statusText}) {
    if (_captureStarted && !_captureFinalized) return;

    _cancelCaptureTimers();
    _faceCenteredSince = null;
    _hasCaptured = false;
    _captureStarted = false;
    _captureFinalized = false;
    _capturedImagePath = null;

    if (!mounted) return;
    setState(() {
      _visualState = _EnrollmentVisualState.guide;
      _countdownSeconds = _captureHoldDuration.inSeconds;
      _statusText = statusText;
    });
  }

  void _cancelCaptureTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _earlyCaptureTimer?.cancel();
    _earlyCaptureTimer = null;
  }

  Future<void> _recoverFromCaptureError(Object error) async {
    _cancelCaptureTimers();
    _faceCenteredSince = null;
    _hasCaptured = false;
    _captureStarted = false;
    _captureFinalized = false;
    _capturedImagePath = null;

    if (!mounted) return;
    setState(() {
      _visualState = _EnrollmentVisualState.guide;
      _countdownSeconds = _captureHoldDuration.inSeconds;
      _statusText = 'Erro na captura/cadastro: $error';
    });
    await _stopEnrollmentStream();
    await _startEnrollment();
  }

  Future<void> _backToCpfInput() async {
    if (_isLeaving) return;
    _isLeaving = true;
    _cancelCaptureTimers();
    await _stopEnrollmentStream();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String? _validateFaceForCapture(Rect faceRect) {
    final center = faceRect.center;
    final dx = center.dx - _guideCenterX;
    final dy = center.dy - _guideCenterY;
    final normalizedDistanceSquared =
        (dx * dx + dy * dy) / (_guideRadius * _guideRadius);
    final faceSize =
        faceRect.width > faceRect.height ? faceRect.width : faceRect.height;
    final faceArea = faceRect.width * faceRect.height;

    if (normalizedDistanceSquared >
        _guideRadiusTolerance * _guideRadiusTolerance) {
      return 'Centralize o rosto no círculo.';
    }

    if (faceRect.width < _minFaceWidth ||
        faceRect.height < _minFaceHeight ||
        faceArea < _minFaceArea) {
      return 'Aproxime o rosto um pouco.';
    }

    if (faceSize > _maxFaceSize) {
      return 'Afaste o rosto um pouco.';
    }

    return null;
  }

  @override
  void dispose() {
    _cancelCaptureTimers();
    unawaited(_faceDetectorService.close());
    unawaited(_stopEnrollmentStream());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller != null && controller.value.isInitialized;

    if (_showIntro) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          return;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0D3E69),
          body: SafeArea(
            child: Stack(
              children: [
                _FaceEnrollmentIntro(onReady: _initializeCamera),
                Positioned(
                  left: 8,
                  top: 12,
                  child: TotemBackButton(
                    onPressed: () => unawaited(_backToCpfInput()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_showSuccess) {
      return const PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Color(0xFF0D3E69),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF1DB53F),
                  size: 110,
                ),
                SizedBox(height: 32),
                Text(
                  'Cadastro concluído!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        return;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight;
                  final maxPreviewHeight = (availableHeight -
                          _logoHeaderHeight -
                          _bottomPanelHeight)
                      .clamp(0.0, double.infinity);
                  final previewHeight = (constraints.maxWidth * 16 / 9)
                      .clamp(0.0, maxPreviewHeight);

                  return Column(
                    children: [
                      // Logo header idêntico ao da tela de identificação.
                      SizedBox(
                        height: _logoHeaderHeight,
                        width: double.infinity,
                        child: Container(
                          color: Colors.white,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 34, vertical: 10),
                          child: Image.asset(
                            'assets/images/logo_vincere.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      if (_isInitializing)
                        SizedBox(
                          height: previewHeight,
                          child:
                              const Center(child: CircularProgressIndicator()),
                        )
                      else if (!isReady)
                        SizedBox(
                          height: previewHeight,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _cameraError ?? 'Falha ao carregar câmera.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: _initializeCamera,
                                    child: const Text('Tentar novamente'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        _EnrollmentPreviewSurface(
                          controller: controller,
                          visualState: _visualState,
                          countdownSeconds: _countdownSeconds,
                          capturedImagePath: _capturedImagePath,
                          mirrorCapturedImage: _selectedCamera?.lensDirection ==
                              CameraLensDirection.front,
                          height: previewHeight,
                          width: constraints.maxWidth,
                        ),
                      Container(
                        height: _bottomPanelHeight,
                        width: double.infinity,
                        color: const Color(0xFF0D3E69),
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                        alignment: Alignment.center,
                        child: Text(
                          _statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Container(color: Colors.white),
                      ),
                    ],
                  );
                },
              ),
              Positioned(
                left: 8,
                top: _logoHeaderHeight + 12,
                child: TotemBackButton(
                  onPressed:
                      _hasCaptured ? null : () => unawaited(_backToCpfInput()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnrollmentPreviewSurface extends StatelessWidget {
  const _EnrollmentPreviewSurface({
    required this.controller,
    required this.visualState,
    required this.countdownSeconds,
    required this.capturedImagePath,
    required this.mirrorCapturedImage,
    required this.height,
    required this.width,
  });

  final CameraController controller;
  final _EnrollmentVisualState visualState;
  final int countdownSeconds;
  final String? capturedImagePath;
  final bool mirrorCapturedImage;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final showCapturedStill = visualState == _EnrollmentVisualState.completed &&
        capturedImagePath != null;
    final capturedStill = showCapturedStill
        ? _CapturedStillImage(
            imagePath: capturedImagePath!,
            mirrorHorizontally: mirrorCapturedImage,
          )
        : null;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return SizedBox(
        width: width,
        height: height,
        child: capturedStill ?? CameraPreview(controller),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.height,
                height: previewSize.width,
                child: capturedStill ?? CameraPreview(controller),
              ),
            ),
          ),
          _FaceEnrollmentOverlay(
            visualState: visualState,
            countdownSeconds: countdownSeconds,
          ),
        ],
      ),
    );
  }
}

class _CapturedStillImage extends StatelessWidget {
  const _CapturedStillImage({
    required this.imagePath,
    required this.mirrorHorizontally,
  });

  final String imagePath;
  final bool mirrorHorizontally;

  @override
  Widget build(BuildContext context) {
    final image = Image.file(File(imagePath), fit: BoxFit.cover);
    if (!mirrorHorizontally) return image;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
      child: image,
    );
  }
}

class _FaceEnrollmentIntro extends StatelessWidget {
  const _FaceEnrollmentIntro({required this.onReady});

  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Vamos fazer seu\ncadastro facial\npara continuar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 42),
          const _EnrollmentInstruction(
            index: '1.',
            text: 'Retire os óculos,\nchapéu ou boné para cadastrar\no rosto.',
          ),
          const SizedBox(height: 26),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image(
                image: AssetImage('assets/images/oculos.png'),
                width: 108,
                height: 86,
                fit: BoxFit.contain,
              ),
              SizedBox(width: 28),
              Image(
                image: AssetImage('assets/images/bone.png'),
                width: 108,
                height: 86,
                fit: BoxFit.contain,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _EnrollmentInstruction(
            index: '2.',
            text: 'Siga as instruções que\nserão exibidas na tela.',
          ),
          const SizedBox(height: 44),
          SizedBox(
            height: 96,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onReady,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF11B7B7),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Estou pronto!',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnrollmentInstruction extends StatelessWidget {
  const _EnrollmentInstruction({
    required this.index,
    required this.text,
  });

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$index $text',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        height: 1.12,
      ),
    );
  }
}

class _FaceEnrollmentOverlay extends StatelessWidget {
  const _FaceEnrollmentOverlay({
    required this.visualState,
    required this.countdownSeconds,
  });

  final _EnrollmentVisualState visualState;
  final int countdownSeconds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final guideWidth = constraints.maxWidth * 0.65;
        final guideHeight = constraints.maxHeight * 0.46;
        final guideLeft = (constraints.maxWidth - guideWidth) / 2;
        final guideTop = constraints.maxHeight * 0.33;
        final bubbleTop = guideTop + guideHeight - 6;

        return Stack(
          children: [
            Positioned(
              left: guideLeft,
              top: guideTop,
              width: guideWidth,
              height: guideHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _ringColor(visualState),
                      width: 5,
                    ),
                  ),
                ),
              ),
            ),
            if (visualState == _EnrollmentVisualState.countdown)
              Positioned(
                top: bubbleTop,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1DB53F),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$countdownSeconds',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            if (visualState == _EnrollmentVisualState.completed)
              Positioned(
                top: bubbleTop,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1DB53F),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _ringColor(_EnrollmentVisualState visualState) {
    switch (visualState) {
      case _EnrollmentVisualState.guide:
        return const Color(0x99B9C0C8);
      case _EnrollmentVisualState.countdown:
      case _EnrollmentVisualState.completed:
        return const Color(0xFF1DB53F);
    }
  }
}

enum _EnrollmentVisualState {
  guide,
  countdown,
  completed,
}
