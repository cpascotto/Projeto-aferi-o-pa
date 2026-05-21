import 'package:flutter/material.dart';

import 'status_message_screen.dart';

/// Msg 6 - Cliente aferiu em menos de 1 hora.
class RecentMeasurementScreen extends StatelessWidget {
  const RecentMeasurementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusMessageScreen(
      icon: Icons.timer_outlined,
      title: 'Voce aferiu\nha pouco tempo',
      subtitle: 'Aguarde antes de realizar uma nova afericao.',
    );
  }
}
