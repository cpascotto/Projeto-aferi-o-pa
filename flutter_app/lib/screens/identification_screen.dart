import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/root_navigation.dart';
import '../providers/identification_provider.dart';
import '../services/cpf_formatter.dart';
import '../widgets/totem_back_button.dart';
import 'blood_pressure_instruction_screen.dart';
import 'cpf_input_screen.dart';

class IdentificationScreen extends ConsumerStatefulWidget {
  const IdentificationScreen({super.key});

  @override
  ConsumerState<IdentificationScreen> createState() =>
      _IdentificationScreenState();
}

class _IdentificationScreenState extends ConsumerState<IdentificationScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(identificationProvider);
    final patient = state.patient;

    if (patient == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          return;
        },
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Paciente não encontrado',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: _restartFlow,
                    child: const Text('Nova identificação'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Prioriza mostrar o NOME — tanto no fluxo de reconhecimento facial
    // quanto no fluxo de Digitar CPF (o N2 também retorna Nome_Cliente).
    // Se por algum motivo o nome não vier, usa o CPF como fallback.
    final hasName = patient.name.isNotEmpty;
    final hasCpf = patient.cpf.isNotEmpty;

    final String displayValue;
    final String confirmTitle;

    if (hasName) {
      displayValue = patient.name;
      confirmTitle = 'É você?';
    } else if (hasCpf) {
      displayValue = formatCpfDigits(patient.cpf);
      confirmTitle = 'Esse é seu CPF?';
    } else {
      displayValue = '';
      confirmTitle = 'Confirmar identificação';
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _CpfConfirmationPanel(
                  key: const ValueKey('cpf-confirmation'),
                  title: confirmTitle,
                  displayValue: displayValue,
                  onConfirm: () => _goToBloodPressureInstructions(patient.id),
                  onReject: _goToCpfRegistration,
                ),
              ),
              Positioned(
                left: 8,
                top: 12,
                child: TotemBackButton(
                  foregroundColor: const Color(0xFF113E69),
                  backgroundColor: const Color(0x14113E69),
                  onPressed: _restartFlow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _restartFlow() {
    ref.read(identificationProvider.notifier).reset();
    popToRootRoute(context);
  }

  void _goToCpfRegistration() {
    ref.read(identificationProvider.notifier).reset();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CpfInputScreen()),
    );
  }

  void _goToBloodPressureInstructions(int patientId) {
    final state = ref.read(identificationProvider);

    // Tanto Início quanto Fim de atendimento passam pela MESMA tela de
    // aferição (instruções + medição + resultado). A diferença está só no
    // botão OK do resultado: Início envia N3, Fim envia F1. Essa decisão
    // é feita dentro da BloodPressureInstructionScreen lendo o
    // attendanceModeProvider.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BloodPressureInstructionScreen(
          patientId: patientId,
          contractId: state.contractId,
          deviceId: state.deviceId ?? '',
          nextInteractionAt: state.nextInteractionAt,
        ),
      ),
    );
  }
}

class _CpfConfirmationPanel extends StatelessWidget {
  const _CpfConfirmationPanel({
    super.key,
    required this.title,
    required this.displayValue,
    required this.onConfirm,
    required this.onReject,
  });

  final String title;
  final String displayValue;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 52),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 33,
              fontWeight: FontWeight.w700,
              color: Color(0xFF113E69),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            displayValue,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: Color(0xFF1D1B20),
            ),
          ),
          const SizedBox(height: 84),
          _IdentificationActionButton(
            label: 'SIM',
            onTap: onConfirm,
            filled: true,
          ),
          const SizedBox(height: 20),
          _IdentificationActionButton(
            label: 'NÃO',
            onTap: onReject,
            filled: false,
          ),
        ],
      ),
    );
  }
}

class _IdentificationActionButton extends StatelessWidget {
  const _IdentificationActionButton({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: filled
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF113E69),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF113E69),
                side: const BorderSide(
                  color: Color(0xFF113E69),
                  width: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}
