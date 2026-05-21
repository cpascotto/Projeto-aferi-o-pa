import 'package:flutter/material.dart';

import 'status_message_screen.dart';

/// Msg 4 - Cliente sem acordo em andamento.
class ClientInactiveScreen extends StatelessWidget {
  const ClientInactiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusMessageScreen(
      icon: Icons.do_not_disturb_alt_outlined,
      title: 'Cliente sem acordo\nem andamento',
      subtitle: 'Procure a recepção para regularizar seu cadastro.',
    );
  }
}
