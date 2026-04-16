import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/blood_pressure_measurement.dart';
import '../navigation/root_navigation.dart';
import '../providers/app_services_provider.dart';
import '../services/blood_pressure_ble_service.dart';

class BloodPressureInstructionScreen extends ConsumerStatefulWidget {
  const BloodPressureInstructionScreen({
    super.key,
    required this.patientId,
  });

  final int patientId;

  @override
  ConsumerState<BloodPressureInstructionScreen> createState() =>
      _BloodPressureInstructionScreenState();
}

class _BloodPressureInstructionScreenState
    extends ConsumerState<BloodPressureInstructionScreen> {
  final BloodPressureBleService _bleService = BloodPressureBleService();

  bool _isLeaving = false;
  bool _isReleased = false;
  BloodPressureMeasurement? _measurement;

  @override
  void initState() {
    super.initState();
    unawaited(_captureMeasurement());
  }

  Future<void> _captureMeasurement() async {
    while (mounted && !_isLeaving && !_isReleased) {
      try {
        final measurement = await _bleService.captureMeasurement();
        await _saveMeasurement(measurement);

        if (!mounted || _isLeaving) return;
        setState(() {
          _measurement = measurement;
          _isReleased = true;
        });
        unawaited(_returnToCameraAfterRelease());
        return;
      } catch (_) {
        if (!mounted || _isLeaving) return;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _saveMeasurement(BloodPressureMeasurement measurement) async {
    while (mounted && !_isLeaving) {
      try {
        await ref.read(apiServiceProvider).registerBloodPressureMeasurement(
              patientId: widget.patientId,
              systolic: measurement.systolic,
              diastolic: measurement.diastolic,
              bpm: measurement.bpm,
              measuredAt: DateTime.now(),
              rawPayload: measurement.rawPayload,
            );
        return;
      } catch (_) {
        if (!mounted || _isLeaving) return;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _returnToCameraAfterRelease() async {
    await Future<void>.delayed(const Duration(seconds: 10));
    if (!mounted || _isLeaving) return;
    _isLeaving = true;
    unawaited(_bleService.stopCapture());
    popToRootRoute(context);
  }

  @override
  void dispose() {
    _isLeaving = true;
    unawaited(_bleService.stopCapture());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        return;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D3E69),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 58, 20, 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _isReleased
                  ? _ReleasedMessage(
                      key: ValueKey('released-message'),
                      measurement: _measurement,
                    )
                  : const _InstructionBody(
                      key: ValueKey('instruction-body'),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstructionBody extends StatelessWidget {
  const _InstructionBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Agora vamos medir sua\npressão com o aparelho\nde aferição',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.07,
          ),
        ),
        SizedBox(height: 78),
        _InstructionStep(
          number: '1.',
          text: 'Coloque a braçadeira no braço\nesquerdo, sem apertar demais',
        ),
        SizedBox(height: 42),
        _DeviceStartStep(),
        SizedBox(height: 40),
        Text(
          'Caso apareça algum desses\nsímbolos na tela, faça o seguinte',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _WarningInstruction(
                imagePath: 'assets/images/indicador_bracadeira.png',
                text:
                    'Braçadeira foi colocada\nestando muito apertada\nou muito frouxa',
              ),
            ),
            SizedBox(width: 30),
            Expanded(
              child: _WarningInstruction(
                imagePath: 'assets/images/detector_movimento.png',
                text:
                    'Foi detectado um\nmovimento corporal\nexcessivo durante a\nmedição',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeviceStartStep extends StatelessWidget {
  const _DeviceStartStep();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: 30,
          child: Text(
            '2.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
        const Expanded(
          child: Text(
            'Após a braçadeira\nestar colocada em seu\nbraço, clique no botão\nazul "START" no\naparelho de aferição',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.03,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Image.asset(
          'assets/images/botao_aparelho.png',
          width: 150,
          height: 150,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}

class _ReleasedMessage extends StatelessWidget {
  const _ReleasedMessage({
    super.key,
    required this.measurement,
  });

  final BloodPressureMeasurement? measurement;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Você está liberado!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          if (measurement != null) ...[
            const SizedBox(height: 34),
            Text(
              '${measurement!.systolic}/${measurement!.diastolic} mmHg',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${measurement!.bpm} bpm',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({
    required this.number,
    required this.text,
  });

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.03,
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningInstruction extends StatelessWidget {
  const _WarningInstruction({
    required this.imagePath,
    required this.text,
  });

  final String imagePath;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          imagePath,
          width: 72,
          height: 72,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
