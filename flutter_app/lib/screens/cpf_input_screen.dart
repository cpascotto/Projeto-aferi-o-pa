import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/identification_provider.dart';
import '../services/cpf_formatter.dart';
import '../widgets/totem_back_button.dart';
import 'face_enrollment_screen.dart';

class CpfInputScreen extends ConsumerStatefulWidget {
  const CpfInputScreen({super.key});

  @override
  ConsumerState<CpfInputScreen> createState() => _CpfInputScreenState();
}

class _CpfInputScreenState extends ConsumerState<CpfInputScreen> {
  static const int _cpfLength = 11;

  String _cpfDigits = '';
  bool _isLeaving = false;

  Future<void> _submit() async {
    if (_cpfDigits.length != _cpfLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CPF deve ter 11 dígitos.')),
      );
      return;
    }

    final ok = await ref.read(identificationProvider.notifier).registerByCpf(
          _cpfDigits,
        );

    if (!mounted) return;

    if (!ok) {
      final state = ref.read(identificationProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage ?? 'Falha no cadastro.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FaceEnrollmentScreen()),
    );
  }

  void _appendDigit(String digit) {
    if (_cpfDigits.length >= _cpfLength) return;
    setState(() {
      _cpfDigits += digit;
    });
  }

  void _removeLastDigit() {
    if (_cpfDigits.isEmpty) return;
    setState(() {
      _cpfDigits = _cpfDigits.substring(0, _cpfDigits.length - 1);
    });
  }

  void _backToConsultation() {
    if (_isLeaving) return;
    _isLeaving = true;
    ref.read(identificationProvider.notifier).reset();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(identificationProvider);
    final isProcessing = state.status == IdentificationStatus.processing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        return;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D3E69),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TotemBackButton(
                    onPressed: isProcessing ? null : _backToConsultation,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Informe seu CPF',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Vamos criar seu cadastro e registrar seu rosto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          height: 78,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _cpfDigits.isEmpty
                                ? '000.000.000-00'
                                : formatCpfDigits(_cpfDigits),
                            style: TextStyle(
                              color: _cpfDigits.isEmpty
                                  ? const Color(0x66113E69)
                                  : const Color(0xFF113E69),
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        _CpfKeyboard(
                          enabled: !isProcessing,
                          onDigit: _appendDigit,
                          onBackspace: _removeLastDigit,
                          onSubmit: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CpfKeyboard extends StatelessWidget {
  const _CpfKeyboard({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final buttonSize =
            ((constraints.maxWidth - (gap * 2)) / 3).clamp(104.0, 122.0);

        return Column(
          children: [
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _KeypadButton(
                      label: row[0],
                      size: buttonSize,
                      enabled: enabled,
                      onTap: () => onDigit(row[0]),
                    ),
                    const SizedBox(width: gap),
                    _KeypadButton(
                      label: row[1],
                      size: buttonSize,
                      enabled: enabled,
                      onTap: () => onDigit(row[1]),
                    ),
                    const SizedBox(width: gap),
                    _KeypadButton(
                      label: row[2],
                      size: buttonSize,
                      enabled: enabled,
                      onTap: () => onDigit(row[2]),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _KeypadButton(
                  size: buttonSize,
                  backgroundColor: const Color(0xFFFF3236),
                  enabled: enabled,
                  onTap: onBackspace,
                  child: const Icon(
                    Icons.backspace_outlined,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
                const SizedBox(width: gap),
                _KeypadButton(
                  label: '0',
                  size: buttonSize,
                  enabled: enabled,
                  onTap: () => onDigit('0'),
                ),
                const SizedBox(width: gap),
                _KeypadButton(
                  size: buttonSize,
                  backgroundColor: const Color(0xFF008A00),
                  enabled: enabled,
                  onTap: onSubmit,
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    this.label,
    this.child,
    this.backgroundColor = Colors.white,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final String? label;
  final Widget? child;
  final Color backgroundColor;
  final double size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color:
            enabled ? backgroundColor : backgroundColor.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Center(
            child: child ??
                Text(
                  label!,
                  style: const TextStyle(
                    color: Color(0xFF07999B),
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
