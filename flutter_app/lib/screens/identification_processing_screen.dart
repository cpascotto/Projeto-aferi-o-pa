import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/identification_provider.dart';
import '../widgets/totem_back_button.dart';
import 'camera_screen.dart';
import 'cpf_input_screen.dart';
import 'identification_screen.dart';

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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const IdentificationScreen()),
      );
      return;
    }

    if (status == IdentificationStatus.notRecognized) {
      final registered = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CpfInputScreen()),
      );
      if (!mounted) return;

      if (registered != true) {
        Navigator.of(context).pop();
      }
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
                    : _ProcessingErrorBody(message: state.errorMessage!),
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

class _ProcessingErrorBody extends ConsumerWidget {
  const _ProcessingErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
