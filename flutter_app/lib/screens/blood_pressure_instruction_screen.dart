import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/blood_pressure_measurement.dart';
import '../navigation/root_navigation.dart';
import '../providers/app_services_provider.dart';
import '../providers/attendance_mode_provider.dart';
import '../services/blood_pressure_ble_service.dart';
import '../services/erp_api_service.dart';
import '../widgets/totem_back_button.dart';
import 'blood_pressure_result_screen.dart';
import 'status/approved_screen.dart';
import 'status/connection_error_screen.dart';
import 'status/out_of_range_screen.dart';
import 'status/thank_you_screen.dart';

class BloodPressureInstructionScreen extends ConsumerStatefulWidget {
  const BloodPressureInstructionScreen({
    super.key,
    required this.patientId,
    this.contractId,
    this.deviceId = '',
    this.nextInteractionAt,
  });

  final int patientId;
  final int? contractId;
  final String deviceId;
  final String? nextInteractionAt;

  @override
  ConsumerState<BloodPressureInstructionScreen> createState() =>
      _BloodPressureInstructionScreenState();
}

class _BloodPressureInstructionScreenState
    extends ConsumerState<BloodPressureInstructionScreen> {
  final BloodPressureBleService _bleService = BloodPressureBleService();

  bool _isLeaving = false;
  bool _isProcessingResult = false;
  bool _isRefusing = false;
  _MeasurementSaveResult? _lastSaveResult;

  @override
  void initState() {
    super.initState();
    unawaited(_captureMeasurementLoop());
  }

  Future<void> _captureMeasurementLoop() async {
    // Garante estado BLE limpo antes da primeira tentativa.
    // Algumas vezes a primeira sessão herda estado de uma medição anterior
    // e o nativo "engasga" — esse stop + delay resolve isso.
    try {
      await _bleService.stopCapture();
    } catch (_) {
      // ignorado — só queremos zerar o estado
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    while (mounted && !_isLeaving) {
      try {
        // Timeout de 90s: se a medição não chegar nesse tempo, jogamos
        // exceção para o catch reiniciar o ciclo (resolve o caso de
        // conexão estabelecida mas medição que não chega).
        final measurement = await _bleService
            .captureMeasurement()
            .timeout(const Duration(seconds: 90));
        if (!mounted || _isLeaving) return;

        // Mostra a tela de resultado com Repetir / OK.
        // Quando OK é apertado, a tela mostra "Enviando aferição..."
        // enquanto chama _registerMeasurement; o resultado fica em
        // _lastSaveResult para ser tratado aqui depois do pop.
        _lastSaveResult = null;
        _isProcessingResult = true;
        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => BloodPressureResultScreen(
              measurement: measurement,
              onConfirm: () async {
                _lastSaveResult = await _registerMeasurement(measurement);
              },
            ),
          ),
        );
        _isProcessingResult = false;

        if (!mounted || _isLeaving) return;

        if (confirmed == true) {
          final result = _lastSaveResult;
          if (result == null || !result.succeeded) {
            _isLeaving = true;
            unawaited(_bleService.stopCapture());
            await Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ConnectionErrorScreen(
                  title: 'Falha ao salvar medição',
                  message:
                      'Não conseguimos enviar sua aferição ao servidor.\nTente novamente em instantes.',
                  detail: result?.errorDetail,
                ),
              ),
            );
            return;
          }

          _isLeaving = true;
          unawaited(_bleService.stopCapture());
          await _navigateAfterMeasurement(result.response);
          return;
        }

        // Se não confirmou (Repetir ou voltou) — re-inicia captura.
      } catch (error) {
        if (!mounted || _isLeaving || _isProcessingResult) return;
        if (_isBleTargetMissing(error)) {
          _isLeaving = true;
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ConnectionErrorScreen(
                title: 'Medidor Bluetooth nao configurado',
                message:
                    'Abra a tela de administrador e selecione o medidor Bluetooth deste totem.',
                detail: error.toString(),
              ),
            ),
          );
          return;
        }

        // Zera sessão BLE antes de tentar de novo — evita ficar preso
        // num estado em que o aparelho está conectado mas a medição
        // não chega no app.
        try {
          await _bleService.stopCapture();
        } catch (_) {
          // ignorado
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  bool _isBleTargetMissing(Object error) {
    return error.toString().contains('Medidor Bluetooth nao configurado');
  }

  Future<_MeasurementSaveResult> _registerMeasurement(
    BloodPressureMeasurement measurement,
  ) async {
    int attempts = 0;
    Object? lastError;
    // Modo escolhido na home:
    //  - inicio → registra a aferição (N3)
    //  - fim    → finaliza o atendimento (F1) ao apertar OK no resultado
    final mode = ref.read(attendanceModeProvider);
    while (mounted && !_isLeaving && attempts < 5) {
      try {
        final contractId = widget.contractId;
        if (contractId == null) {
          throw Exception('Contrato ERP não disponível — medição não pode ser registrada.');
        }

        final ErpResponse response;
        if (mode == AttendanceMode.fim) {
          // Fim de atendimento: mesmo fluxo de aferição, mas no OK do
          // resultado chamamos F1 (finaliza) em vez de N3.
          response = await ref.read(erpApiServiceProvider).finalizeSession(
                deviceId: widget.deviceId,
                clientId: widget.patientId,
                contractId: contractId,
                nextInteractionAt: widget.nextInteractionAt,
              );
        } else {
          // Início de atendimento: registra a medição (N3).
          response = await ref.read(erpApiServiceProvider).registerMeasurement(
                deviceId: widget.deviceId,
                clientId: widget.patientId,
                contractId: contractId,
                nextInteractionAt: widget.nextInteractionAt,
                systolic: measurement.systolic,
                diastolic: measurement.diastolic,
                bpm: measurement.bpm,
                rawPayload: measurement.rawPayload,
              );
        }
        return _MeasurementSaveResult.successWithErp(response);
      } catch (error) {
        lastError = error;
        attempts++;
        if (!mounted || _isLeaving) {
          return _MeasurementSaveResult.failure(error);
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return _MeasurementSaveResult.failure(lastError);
  }

  Future<void> _navigateAfterMeasurement(ErpResponse? response) async {
    // Fim de atendimento: o OK já chamou F1 (finaliza). Não há aferição a
    // avaliar — vai direto para a tela de encerramento.
    if (ref.read(attendanceModeProvider) == AttendanceMode.fim) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ThankYouScreen()),
      );
      return;
    }

    // 7=Sistólica fora, 14=Diastólica fora, 15=BPM fora, 16=Aguardar Fisio
    if (response?.message == 7 ||
        response?.message == 14 ||
        response?.message == 15 ||
        response?.message == 16) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OutOfRangeScreen()),
      );
      return;
    }

    if (response?.message == 8) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ApprovedScreen()),
      );
      return;
    }

    if (response?.message == 9) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ThankYouScreen()),
      );
      return;
    }

    // Encerra a sessão no ERP, se houver. Falhas aqui não bloqueiam
    // o fluxo do usuário — a medição já foi salva.
    final contractId = widget.contractId;
    if (contractId != null) {
      try {
        await ref.read(erpApiServiceProvider).finalizeSession(
              deviceId: widget.deviceId,
              clientId: widget.patientId,
              contractId: contractId,
              nextInteractionAt: widget.nextInteractionAt,
            );
      } catch (_) {
        // Ignorado — segue o fluxo visual.
      }
      if (!mounted) return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ApprovedScreen()),
    );
  }

  // "Não quero aferir" → registra a recusa via N4, NOS DOIS MODOS
  // (Início e Fim).
  //
  // NOTA SOBRE O DIAGRAMA: hoje NÃO existe F1 para a recusa — nem no diagrama
  // nem na regra atual. Por isso a recusa sempre chama N4, mesmo no modo Fim.
  // (Só o botão OK do resultado é que dispara F1 no modo Fim.)
  // Caso no futuro a recusa também precise finalizar via F1, o ponto de
  // implementação é aqui: após o registerRefusal, chamar finalizeSession.
  Future<void> _refuseMeasurement() async {
    if (_isLeaving || _isRefusing) return;
    _isLeaving = true;

    // Mostra overlay de loading enquanto o N4 é processado.
    if (mounted) {
      setState(() => _isRefusing = true);
    }

    unawaited(_bleService.stopCapture());

    final contractId = widget.contractId;
    if (contractId != null) {
      try {
        final response = await ref.read(erpApiServiceProvider).registerRefusal(
              deviceId: widget.deviceId,
              clientId: widget.patientId,
              contractId: contractId,
              nextInteractionAt: widget.nextInteractionAt,
            );
        if (!mounted) return;
        if (response.message == 8) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ApprovedScreen()),
          );
          return;
        }
        if (response.message == 9) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ThankYouScreen()),
          );
          return;
        }
      } catch (_) {
        // Mesmo sem rede, encerra o fluxo visualmente.
      }
    }

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ThankYouScreen()),
    );
  }

  @override
  void dispose() {
    _isLeaving = true;
    unawaited(_bleService.stopCapture());
    super.dispose();
  }

  void _backToStart() {
    if (_isLeaving || _isRefusing) return;
    _isLeaving = true;
    unawaited(_bleService.stopCapture());
    popToRootRoute(context);
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
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 60, 18, 12),
                child: Column(
                  children: [
                    const Expanded(
                      child: _InstructionViewport(
                        child: _InstructionBody(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _RefuseButton(
                      enabled: !_isRefusing,
                      onPressed: () => unawaited(_refuseMeasurement()),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 8,
                top: 12,
                child: TotemBackButton(
                  onPressed: _isRefusing ? null : _backToStart,
                ),
              ),
              if (_isRefusing) const _RefusingOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Overlay mostrado enquanto o N4 é processado ─────────────────────────────

class _RefusingOverlay extends StatelessWidget {
  const _RefusingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC0D3E69),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 5,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Encerrando atendimento...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionViewport extends StatelessWidget {
  const _InstructionViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: constraints.maxWidth,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _InstructionBody extends StatelessWidget {
  const _InstructionBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Agora vamos medir sua\npressão com o aparelho\nde aferição',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.07,
          ),
        ),
        SizedBox(height: 28),
        _InstructionStep(
          number: '1.',
          text: 'Coloque a braçadeira no braço\nesquerdo, sem apertar demais',
        ),
        SizedBox(height: 18),
        _DeviceStartStep(),
        SizedBox(height: 18),
        Text(
          'Caso apareça algum desses\nsímbolos na tela, faça o seguinte',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        SizedBox(height: 10),
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
            SizedBox(width: 18),
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
              fontSize: 17,
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
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.03,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Image.asset(
          'assets/images/botao_aparelho.png',
          width: 112,
          height: 112,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}

class _MeasurementSaveResult {
  const _MeasurementSaveResult._({
    required this.succeeded,
    this.response,
    this.errorDetail,
  });

  factory _MeasurementSaveResult.successWithErp(ErpResponse response) =>
      _MeasurementSaveResult._(succeeded: true, response: response);

  factory _MeasurementSaveResult.failure(Object? error) =>
      _MeasurementSaveResult._(
        succeeded: false,
        errorDetail: error?.toString(),
      );

  final bool succeeded;
  final ErpResponse? response;
  final String? errorDetail;
}

class _RefuseButton extends StatelessWidget {
  const _RefuseButton({
    required this.onPressed,
    this.enabled = true,
  });

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: Colors.white.withValues(alpha: enabled ? 0.6 : 0.25),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Não quero aferir',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
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
              fontSize: 17,
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
              fontSize: 18,
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
          width: 56,
          height: 56,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            height: 1.28,
          ),
        ),
      ],
    );
  }
}
