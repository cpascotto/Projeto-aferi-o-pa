import 'package:flutter/material.dart';

import 'status_message_screen.dart';

/// Msg 9 - OBRIGADO, bom descanso. Tela final do atendimento.
class ThankYouScreen extends StatelessWidget {
  const ThankYouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusMessageScreen(
      title: 'Obrigado!',
      subtitle: 'Tenha um bom descanso.',
      autoReturn: Duration(seconds: 5),
    );
  }
}
