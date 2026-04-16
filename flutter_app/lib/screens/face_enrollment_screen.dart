import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  static const Duration _completedStateDuration = Duration(milliseconds: 550);
  static const double _guideCenterX = 0.5;
  static const double _guideCenterY = 0.50;
  static const double _guideRadius = 0.28;
  static const double _guideRadiusTolerance = 1.45;
  static const double _minFaceWidth = 0.20;
  static const double _minFaceHeight = 0.24;
  static const double _minFaceArea = 0.052;
  static const double _maxFaceSize = 0.72;
  static const double _bottomPanelHeight = 135;
  static const String _captureType = 'front_single';

  CameraController? _controller;
  CameraDescription? _selectedCamera;
  late FaceDetectorService _faceDetectorService;

  bool _processingFrame = false;
  bool _hasCaptured = false;
  bool _isStreaming = false;
  bool _isInitializing = true;
  bool _showIntro = true;
  bool _isLeaving = false;

  String? _cameraError;
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

    if (!mounted) return;
    setState(() {
      _hasCaptured = false;
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

      if (faceRect == null || _hasCaptured) {
        _faceCenteredSince = null;
        if (mounted) {
          setState(() {
            _visualState = _EnrollmentVisualState.guide;
            _countdownSeconds = _captureHoldDuration.inSeconds;
            if (_isStreaming) {
              _statusText = 'Centralize o rosto no círculo.';
            }
          });
        }
        return;
      }

      final validationMessage = _validateFaceForCapture(faceRect);
      final now = DateTime.now();

      if (validationMessage != null) {
        _faceCenteredSince = null;
        if (mounted) {
          setState(() {
            _visualState = _EnrollmentVisualState.guide;
            _countdownSeconds = _captureHoldDuration.inSeconds;
            _statusText = validationMessage;
          });
        }
        return;
      }

      _faceCenteredSince ??= now;
      final elapsed = now.difference(_faceCenteredSince!);
      final remaining = (_captureHoldDuration - elapsed).inMilliseconds;
      final countdown = remaining > 0 ? (remaining / 1000).ceil() : 0;

      if (mounted) {
        setState(() {
          _visualState = _EnrollmentVisualState.countdown;
          _countdownSeconds = countdown.clamp(1, 3);
          _statusText = 'Não se mova, estamos cadastrando seu rosto';
        });
      }

      if (elapsed < _captureHoldDuration) {
        return;
      }

      await _captureFaceSample();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _visualState = _EnrollmentVisualState.guide;
        _statusText = 'Erro na captura/cadastro: $error';
      });
      _hasCaptured = false;
      await _stopEnrollmentStream();
      await _startEnrollment();
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _captureFaceSample() async {
    final controller = _controller;
    final patient = ref.read(identificationProvider).patient;

    if (controller == null || patient == null || _hasCaptured) {
      return;
    }

    _hasCaptured = true;
    await _stopEnrollmentStream();

    if (mounted) {
      setState(() {
        _visualState = _EnrollmentVisualState.completed;
        _statusText = 'Concluído';
      });
    }

    final picture = await controller.takePicture();
    final ok = await ref
        .read(identificationProvider.notifier)
        .registerFaceSampleFromImagePath(
          patientId: patient.id,
          captureType: _captureType,
          imagePath: picture.path,
        );

    if (!mounted) return;

    if (!ok) {
      final state = ref.read(identificationProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.errorMessage ?? 'Falha ao cadastrar rosto.'),
        ),
      );
      _hasCaptured = false;
      _faceCenteredSince = null;
      _countdownSeconds = _captureHoldDuration.inSeconds;
      _visualState = _EnrollmentVisualState.guide;
      _statusText = 'Falha ao salvar. Reposicione o rosto.';
      await _startEnrollment();
      return;
    }

    await Future<void>.delayed(_completedStateDuration);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const IdentificationScreen()),
    );
  }

  Future<void> _backToCpfInput() async {
    if (_isLeaving) return;
    _isLeaving = true;
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
                  final previewHeight = (constraints.maxWidth * 16 / 9)
                      .clamp(0.0, availableHeight - _bottomPanelHeight);

                  return Column(
                    children: [
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
                top: 12,
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
    required this.height,
    required this.width,
  });

  final CameraController controller;
  final _EnrollmentVisualState visualState;
  final int countdownSeconds;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return SizedBox(
        width: width,
        height: height,
        child: CameraPreview(controller),
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
                child: CameraPreview(controller),
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
