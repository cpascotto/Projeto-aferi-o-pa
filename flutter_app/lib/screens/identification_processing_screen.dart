import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_model.dart';
import '../navigation/erp_flow_navigation.dart';
import '../providers/app_services_provider.dart';
import '../providers/debug_log_provider.dart';
import '../providers/identification_provider.dart';
import '../widgets/totem_back_button.dart';
import 'camera_screen.dart';
import 'cpf_input_screen.dart';
import 'identification_screen.dart';
import 'status/connection_error_screen.dart';
import 'status/equipment_not_configured_screen.dart';

class IdentificationProcessingScreen extends ConsumerStatefulWidget {
  const IdentificationProcessingScreen({
    super.key,
    required this.imagePath,
  });

  final String imagePath;

  @override
  ConsumerState<IdentificationProcessingScreen> createState() =>
      _IdentificationProcessingScreenState();
}

class _IdentificationProcessingScreenState
    extends ConsumerState<IdentificationProcessingScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runIdentification());
  }

  Future<void> _runIdentification() async {
    if (_started) return;
    _started = true;

    final notifier = ref.read(identificationProvider.notifier);
    notifier.startAttempt();

    final status = await notifier.identifyFromImagePath(widget.imagePath);
    if (!mounted) return;

    if (status == IdentificationStatus.recognized) {
      await _validateRecognized();
      return;
    }

    if (status == IdentificationStatus.notRecognized) {
      final registered = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const CpfInputScreen(
            mode: CpfInputMode.updateFaceThenMeasurement,
          ),
        ),
      );
      if (!mounted) return;

      if (registered != true) {
        Navigator.of(context).pop();
      }
      return;
    }

    // status == error → mostrado abaixo no build, com botão voltar.
  }

  Future<void> _validateRecognized() async {
    try {
      final state = ref.read(identificationProvider);
      final equipmentSettings = ref.read(equipmentSettingsServiceProvider);
      final unitId = await equipmentSettings.getUnitId();
      final deviceId = await equipmentSettings.getDeviceId();

      if (unitId.isEmpty || deviceId.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const EquipmentNotConfiguredScreen(),
          ),
        );
        return;
      }

      final log = ref.read(debugLogControllerProvider.notifier);
      final embLen = state.faceEmbedding?.length ?? 0;
      final embPreview = state.faceEmbedding != null && state.faceEmbedding!.length >= 10
          ? '${state.faceEmbedding!.take(5).map((v) => v.toStringAsFixed(4)).join(',')} ... ${state.faceEmbedding!.skip(state.faceEmbedding!.length - 5).map((v) => v.toStringAsFixed(4)).join(',')}'
          : '(vazio)';
      unawaited(log.recordLog(
        'N1 IDENTIFICACAO: embeddingLen=$embLen unitId=$unitId deviceId=$deviceId\nEMBEDDING_PREVIEW: [$embPreview]',
        source: 'identification',
      ));

      final response =
          await ref.read(erpApiServiceProvider).validateBiometric(
                unitId: unitId,
                deviceId: deviceId,
                recognizedAt: DateTime.now(),
                faceEmbedding: state.faceEmbedding,
              );

      unawaited(log.recordLog(
        'N1 RESP: msg=${response.message} clientId=${response.clientId} contractId=${response.contractId}',
        source: 'identification',
        context: {'raw': response.raw?.toString() ?? 'null'},
      ));

      if (!mounted) return;

      // Msg=3: cliente ativo com biometria reconhecida.
      // Armazena os dados do ERP e leva para "Esse é seu CPF?" antes da aferição.
      if (response.message == 3) {
        final clientId = response.clientId;
        final contractId = response.contractId;
        if (clientId != null && contractId != null) {
          final patient = PatientModel(
            id: clientId,
            name: response.clientName ?? '',
            cpf: response.cpf ?? '',
            faceEmbeddings: const [],
          );
          ref.read(identificationProvider.notifier).setErpData(
                patient: patient,
                contractId: contractId,
                deviceId: deviceId,
                nextInteractionAt: response.nextInteractionAt,
              );
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const IdentificationScreen()),
        );
        return;
      }

      await navigateByErpResponse(
        context,
        response,
        deviceId: deviceId,
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConnectionErrorScreen(
            message:
                'Não conseguimos validar sua identificação no servidor agora.\nVerifique a conexão e tente novamente.',
            detail: error.toString(),
            onRetry: () {
              Navigator.of(context).pop();
              _validateRecognized();
            },
          ),
        ),
      );
    }
  }

  void _backToCamera() {
    ref.read(identificationProvider.notifier).reset();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(identificationProvider);

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
              SizedBox.expand(
                child: state.errorMessage == null
                    ? const _ConsultingBody()
                    : _ProcessingErrorBody(
                        message: state.errorMessage!,
                        onRetry: _backToCamera,
                      ),
              ),
              Positioned(
                left: 8,
                top: 12,
                child: TotemBackButton(onPressed: _backToCamera),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsultingBody extends StatefulWidget {
  const _ConsultingBody();

  @override
  State<_ConsultingBody> createState() => _ConsultingBodyState();
}

class _ConsultingBodyState extends State<_ConsultingBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 8),
        RotationTransition(
          turns: _controller,
          child: CustomPaint(
            size: const Size(76, 76),
            painter: _ConsultingSpinnerPainter(),
          ),
        ),
        const SizedBox(height: 44),
        const Text(
          'Consultando...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(flex: 9),
      ],
    );
  }
}

class _ProcessingErrorBody extends StatelessWidget {
  const _ProcessingErrorBody({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFFC857),
            size: 84,
          ),
          const SizedBox(height: 24),
          const Text(
            'Não conseguimos identificar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 60,
            child: ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07999B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Tentar novamente',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsultingSpinnerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawCircle(
      rect.center,
      size.width / 2.3,
      shadowPaint,
    );

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFB7D7F3),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect.deflate(8),
      0,
      6.1,
      false,
      trackPaint,
    );

    canvas.drawArc(
      rect.deflate(8),
      -0.8,
      3.8,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
