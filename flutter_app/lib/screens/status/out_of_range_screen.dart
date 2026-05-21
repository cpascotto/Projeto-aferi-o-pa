import 'package:flutter/material.dart';

import 'status_message_screen.dart';

/// Msg 7  - Sistólica fora da normalidade
/// Msg 14 - Diastólica fora da normalidade
/// Msg 15 - BPM fora da normalidade
/// Msg 16 - Aguardar Fisioterapeuta
class OutOfRangeScreen extends StatelessWidget {
  const OutOfRangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusMessageScreen(
      icon: Icons.warning_amber_rounded,
      iconColor: Color(0xFFFFC857),
      title: 'Valores fora\nda normalidade',
      subtitle: 'Aguarde o atendimento do fisioterapeuta.',
      autoReturn: Duration(seconds: 12),
    );
  }
}
