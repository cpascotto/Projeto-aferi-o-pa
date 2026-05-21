import 'package:flutter/material.dart';

import 'status_message_screen.dart';

/// Msg 2 - Cliente não encontrado.
class ClientNotFoundScreen extends StatelessWidget {
  const ClientNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusMessageScreen(
      icon: Icons.person_off_outlined,
      title: 'Cliente não cadastrado',
      subtitle: 'Procure a recepção para realizar seu cadastro.',
    );
  }
}
