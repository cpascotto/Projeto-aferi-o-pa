import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/attendance_mode_provider.dart';
import '../providers/identification_provider.dart';
import 'admin_screen.dart';
import 'camera_screen.dart';

/// Tela inicial do totem (home permanente).
///
/// Mostra a logo no topo e dois botões:
///  - Início de atendimento → identifica e afere (N3)
///  - Fim de atendimento     → identifica e finaliza (F1)
///
/// Em ambos, o fluxo de identificação facial é o mesmo; o modo escolhido
/// aqui é guardado no [attendanceModeProvider] e lido depois da confirmação
/// de identidade para decidir entre aferir (N3) ou finalizar (F1).
class AttendanceModeScreen extends ConsumerStatefulWidget {
  const AttendanceModeScreen({super.key});

  @override
  ConsumerState<AttendanceModeScreen> createState() =>
      _AttendanceModeScreenState();
}

class _AttendanceModeScreenState extends ConsumerState<AttendanceModeScreen> {
  int _logoTapCount = 0;
  Timer? _logoTapResetTimer;

  void _start(AttendanceMode mode) {
    // Define o modo e zera qualquer estado de identificação anterior.
    ref.read(attendanceModeProvider.notifier).state = mode;
    ref.read(identificationProvider.notifier).reset();

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  void _handleLogoTap() {
    _logoTapResetTimer?.cancel();
    _logoTapCount += 1;
    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      );
      return;
    }
    _logoTapResetTimer = Timer(const Duration(seconds: 2), () {
      _logoTapCount = 0;
    });
  }

  @override
  void dispose() {
    _logoTapResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Logo no topo (5 toques abrem o admin).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleLogoTap,
              child: Container(
                height: 110,
                width: double.infinity,
                color: Colors.white,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
                child: Image.asset(
                  'assets/images/logo_vincere.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 2),
                    const Text(
                      'Bem-vindo!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF0D3E69),
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Selecione uma opção para continuar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF5A6B7B),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const Spacer(flex: 3),

                    // Início de atendimento
                    _AttendanceButton(
                      label: 'Início de atendimento',
                      icon: Icons.login_rounded,
                      filled: true,
                      onTap: () => _start(AttendanceMode.inicio),
                    ),
                    const SizedBox(height: 20),

                    // Fim de atendimento
                    _AttendanceButton(
                      label: 'Fim de atendimento',
                      icon: Icons.logout_rounded,
                      filled: false,
                      onTap: () => _start(AttendanceMode.fim),
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceButton extends StatelessWidget {
  const _AttendanceButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF0D3E69);
    return SizedBox(
      height: 92,
      child: filled
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 30),
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: azul,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 30),
              label: Text(
                label,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: azul,
                side: const BorderSide(color: azul, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
    );
  }
}
