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

    // Se vier do reconhecimento facial (N1), o CPF pode estar vazio.
    // Nesse caso mostra o nome do paciente como identificação.
    final hasCpf = patient.cpf.isNotEmpty;
    final displayValue =
        hasCpf ? formatCpfDigits(patient.cpf) : patient.name;
    final confirmTitle = hasCpf ? 'Esse é seu CPF?' : 'É você?';

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
