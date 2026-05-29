import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_route_observer.dart';
import '../providers/identification_provider.dart';
import '../services/blood_pressure_ble_service.dart';
import '../services/face_detector_service.dart';
import '../widgets/totem_back_button.dart';
import 'admin_screen.dart';
import 'cpf_input_screen.dart';
import 'identification_processing_screen.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with RouteAware, WidgetsBindingObserver {
  static const Duration _captureHoldDuration = Duration(seconds: 3);
  static const Duration _earlyCaptureAt = Duration(milliseconds: 1500);
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
  static const double _logoHeaderHeight = 92;

  CameraController? _controller;
  CameraDescription? _selectedCamera;
  late FaceDetectorService _faceDetectorService;
  final BloodPressureBleService _bleService = BloodPressureBleService();
  Timer? _logoTapResetTimer;
  Timer? _countdownTimer;
  Timer? _earlyCaptureTimer;

  bool _processingFrame = false;
  bool _hasCaptured = false;
  bool _captureStarted = false;
  bool _captureFinalized = false;
  bool _isStreaming = false;
  bool _isInitializing = true;
  bool _isRestartingCamera = false;

  String? _cameraError;
  String? _capturedImagePath;
  String _statusText = 'Inicializando câmera...';

  DateTime? _faceCenteredSince;
  int _countdownSeconds = _captureHoldDuration.inSeconds;
  int _logoTapCount = 0;
  _IdentificationVisualState _visualState = _IdentificationVisualState.guide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetectorService = FaceDetectorService();
    unawaited(_initializeCamera());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    unawaited(_pauseCamera());
  }

  @override
  void didPopNext() {
    unawaited(_resumeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_pauseCamera(updateUi: false));
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    if (_isRestartingCamera) return;
    _isRestartingCamera = true;

    setState(() {
      _isInitializing = true;
      _cameraError = null;
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

      await _disposeCameraController(updateUi: false);
      _controller = controller;
      _selectedCamera = frontCamera;

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });

      unawaited(_checkBluetooth());
      await _startIdentification();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _cameraError = error.toString();
        _statusText = 'Falha ao acessar câmera.';
      });
    } finally {
      _isRestartingCamera = false;
    }
  }

  Future<void> _pauseCamera({bool updateUi = true}) async {
    await _disposeCameraController(updateUi: updateUi);
  }

  Future<void> _resumeCamera() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (_isRestartingCamera) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      await _initializeCamera();
      return;
    }

    if (_isInitializing) return;

    await _startIdentification();
  }

  Future<void> _disposeCameraController({bool updateUi = true}) async {
    _cancelCaptureTimers();
    final controller = _controller;
    _controller = null;
    _selectedCamera = null;
    _isStreaming = false;
    _processingFrame = false;
    _captureStarted = false;
    _captureFinalized = false;
    _capturedImagePath = null;

    if (updateUi && mounted) {
      setState(() {
        _hasCaptured = false;
        _faceCenteredSince = null;
        _countdownSeconds = _captureHoldDuration.inSeconds;
        _visualState = _IdentificationVisualState.guide;
        _isInitializing = true;
        _cameraError = null;
        _statusText = 'Inicializando câmera...';
      });
    }

    if (controller == null) return;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // O controller sera descartado de qualquer forma.
    }

    await controller.dispose();
  }

  Future<void> _startIdentification() async {
    if (ModalRoute.of(context)?.isCurrent != true) return;

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
      _visualState = _IdentificationVisualState.guide;
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

  Future<void> _stopIdentificationStream() async {
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
        await _captureIdentificationPhoto(fromValidatedFrame: true);
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

  Future<void> _captureIdentificationPhoto({
    bool fromValidatedFrame = false,
  }) async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _captureStarted ||
        _captureFinalized ||
        _faceCenteredSince == null) {
      return;
    }

    if (_processingFrame && !fromValidatedFrame) {
      _earlyCaptureTimer?.cancel();
      _earlyCaptureTimer = Timer(
        const Duration(milliseconds: 120),
        () => unawaited(_captureIdentificationPhoto()),
      );
      return;
    }

    _captureStarted = true;
    _hasCaptured = true;
    _earlyCaptureTimer?.cancel();

    try {
      await _stopIdentificationStream();
      final picture = await controller.takePicture();
      _capturedImagePath = picture.path;

      if (_isHoldComplete) {
        await _openIdentificationProcessing(picture.path);
      }
    } catch (error) {
      await _recoverFromCaptureError(error);
    }
  }

  Future<void> _finishCaptureHold() async {
    if (_captureFinalized) return;

    _countdownTimer?.cancel();

    if (!_captureStarted) {
      await _captureIdentificationPhoto();
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

    await _openIdentificationProcessing(imagePath);
  }

  Future<void> _openIdentificationProcessing(String imagePath) async {
    if (_captureFinalized) return;

    _captureFinalized = true;
    _cancelCaptureTimers();

    if (mounted) {
      setState(() {
        _visualState = _IdentificationVisualState.completed;
        _statusText = 'Concluído';
      });
    }

    await Future<void>.delayed(_completedStateDuration);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IdentificationProcessingScreen(
          imagePath: imagePath,
        ),
      ),
    );

    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent == true) {
      await _resumeCamera();
    }
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
      () => unawaited(_captureIdentificationPhoto()),
    );
  }

  void _updateCountdownFromTimer() {
    final startedAt = _faceCenteredSince;
    if (startedAt == null || _captureFinalized) return;

    final elapsed = DateTime.now().difference(startedAt);
    _updateCountdownUi(elapsed);

    if (elapsed >= _captureHoldDuration) {
      _countdownTimer?.cancel();
      unawaited(_finishCaptureHold());
    }
  }

  void _updateCountdownUi(Duration elapsed) {
    if (!mounted || _captureFinalized) return;

    final remaining = (_captureHoldDuration - elapsed).inMilliseconds;
    final countdown = remaining > 0 ? (remaining / 1000).ceil() : 1;

    setState(() {
      _visualState = _IdentificationVisualState.countdown;
      _countdownSeconds = countdown.clamp(1, 3);
      _statusText = remaining <= 0 && _capturedImagePath == null
          ? 'Capturando foto...'
          : 'Não se mova, estamos identificando você';
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
      _visualState = _IdentificationVisualState.guide;
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
      _visualState = _IdentificationVisualState.guide;
      _countdownSeconds = _captureHoldDuration.inSeconds;
      _statusText = 'Erro na captura/identificação: $error';
    });
    await _stopIdentificationStream();
    await _resumeCamera();
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

  void _handleLogoTap() {
    _logoTapResetTimer?.cancel();
    _logoTapCount += 1;

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _showAdminPanel();
      return;
    }

    _logoTapResetTimer = Timer(const Duration(seconds: 2), () {
      _logoTapCount = 0;
    });
  }

  Future<void> _checkBluetooth() async {
    try {
      final enabled = await _bleService.isBluetoothEnabled();
      if (enabled || !mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Bluetooth desligado'),
          content: const Text(
            'O Bluetooth é necessário para realizar a aferição de pressão arterial. Deseja ativá-lo agora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Agora não'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _bleService.requestEnableBluetooth();
              },
              child: const Text(
                'Ativar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      // Ignora se BLE nao estiver disponivel no dispositivo.
    }
  }

  void _showAdminPanel() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      ),
    );
  }

  void _openCpfInput() {
    if (_hasCaptured) return;

    ref.read(identificationProvider.notifier).reset();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CpfInputScreen(
          mode: CpfInputMode.measurementOnly,
        ),
      ),
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _logoTapResetTimer?.cancel();
    unawaited(_faceDetectorService.close());
    unawaited(_disposeCameraController(updateUi: false));
    super.dispose();
  }

  // Volta para a tela inicial (escolha Início/Fim de atendimento).
  void _backToHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final maxPreviewHeight =
                (availableHeight - _logoHeaderHeight - _bottomPanelHeight)
                    .clamp(0.0, double.infinity);
            final previewHeight =
                (constraints.maxWidth * 16 / 9).clamp(0.0, maxPreviewHeight);

            return Column(
              children: [
                _IdentificationLogoHeader(
                  height: _logoHeaderHeight,
                  onTap: _handleLogoTap,
                ),
                if (_isInitializing)
                  SizedBox(
                    height: previewHeight,
                    child: const Center(child: CircularProgressIndicator()),
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
                  SizedBox(
                    height: previewHeight,
                    width: constraints.maxWidth,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _CameraPreviewSurface(
                          controller: controller,
                          visualState: _visualState,
                          countdownSeconds: _countdownSeconds,
                          capturedImagePath: _capturedImagePath,
                          mirrorCapturedImage: _selectedCamera?.lensDirection ==
                              CameraLensDirection.front,
                          height: previewHeight,
                          width: constraints.maxWidth,
                        ),
                        if (!_hasCaptured)
                          Positioned(
                            left: 28,
                            right: 28,
                            bottom: 8,
                            child: _CpfShortcutButton(
                              onPressed: _openCpfInput,
                            ),
                          ),
                      ],
                    ),
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
            // Botão voltar para a tela inicial (Início/Fim de atendimento).
            Positioned(
              left: 8,
              top: 8,
              child: TotemBackButton(
                foregroundColor: const Color(0xFF113E69),
                backgroundColor: const Color(0x14113E69),
                onPressed: _backToHome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CpfShortcutButton extends StatelessWidget {
  const _CpfShortcutButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.dialpad_rounded, size: 24),
        label: const Text(
          'Digitar CPF',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0D3E69),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _IdentificationLogoHeader extends StatelessWidget {
  const _IdentificationLogoHeader({
    required this.height,
    required this.onTap,
  });

  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        width: double.infinity,
        color: Colors.white,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 10),
        child: Image.asset(
          'assets/images/logo_vincere.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _CameraPreviewSurface extends StatelessWidget {
  const _CameraPreviewSurface({
    required this.controller,
    required this.visualState,
    required this.countdownSeconds,
    required this.capturedImagePath,
    required this.mirrorCapturedImage,
    required this.height,
    required this.width,
  });

  final CameraController controller;
  final _IdentificationVisualState visualState;
  final int countdownSeconds;
  final String? capturedImagePath;
  final bool mirrorCapturedImage;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final showCapturedStill =
        visualState == _IdentificationVisualState.completed &&
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
          _FaceTrackingOverlay(
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

class _FaceTrackingOverlay extends StatelessWidget {
  const _FaceTrackingOverlay({
    required this.visualState,
    required this.countdownSeconds,
  });

  final _IdentificationVisualState visualState;
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
            if (visualState == _IdentificationVisualState.countdown)
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
            if (visualState == _IdentificationVisualState.completed)
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

  Color _ringColor(_IdentificationVisualState visualState) {
    switch (visualState) {
      case _IdentificationVisualState.guide:
        return const Color(0x99B9C0C8);
      case _IdentificationVisualState.countdown:
      case _IdentificationVisualState.completed:
        return const Color(0xFF1DB53F);
    }
  }
}

enum _IdentificationVisualState {
  guide,
  countdown,
  completed,
}
