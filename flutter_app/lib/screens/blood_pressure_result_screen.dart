import 'package:flutter/material.dart';

import '../models/blood_pressure_measurement.dart';

/// Tela que mostra os valores capturados da aferição com botões
/// "Repetir" (refazer a medição) e "OK" (confirmar e prosseguir).
///
/// Pop devolve:
///   - true  => OK (confirmou)
///   - false => Repetir
///   - null  => fechou de outra forma
///
/// Se [onConfirm] for fornecido, ele é executado quando o usuário aperta OK
/// e a tela mostra um overlay "Salvando..." enquanto o Future não completa.
/// Só faz pop(true) depois que [onConfirm] termina sem lançar erro.
class BloodPressureResultScreen extends StatefulWidget {
  const BloodPressureResultScreen({
    super.key,
    required this.measurement,
    this.onConfirm,
  });

  final BloodPressureMeasurement measurement;
  final Future<void> Function()? onConfirm;

  @override
  State<BloodPressureResultScreen> createState() =>
      _BloodPressureResultScreenState();
}

class _BloodPressureResultScreenState extends State<BloodPressureResultScreen> {
  bool _isProcessing = false;

  Future<void> _onOkPressed() async {
    if (_isProcessing) return;
    final onConfirm = widget.onConfirm;
    if (onConfirm == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await onConfirm();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop(true);
      }
    }
  }

  void _onRepeatPressed() {
    if (_isProcessing) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        backgroundColor: const Color(0xFF0D3E69),
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      'Valores da sua\naferição',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ValueRow(
                              label: 'Sistólica',
                              value: '${widget.measurement.systolic}',
                              unit: 'mmHg',
                            ),
                            const SizedBox(height: 18),
                            _ValueRow(
                              label: 'Diastólica',
                              value: '${widget.measurement.diastolic}',
                              unit: 'mmHg',
                            ),
                            const SizedBox(height: 18),
                            _ValueRow(
                              label: 'BPM',
                              value: '${widget.measurement.bpm}',
                              unit: 'bpm',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            label: 'Repetir',
                            background: Colors.white,
                            foreground: const Color(0xFF0D3E69),
                            enabled: !_isProcessing,
                            onPressed: _onRepeatPressed,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ActionButton(
                            label: 'OK',
                            background: const Color(0xFF07999B),
                            foreground: Colors.white,
                            enabled: !_isProcessing,
                            onPressed: _onOkPressed,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isProcessing) const _SavingOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay();

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
                'Enviando aferição...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
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

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            unit,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.55),
          disabledForegroundColor: foreground.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
