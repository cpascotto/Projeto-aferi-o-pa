import 'package:flutter/material.dart';

import '../screens/blood_pressure_instruction_screen.dart';
import '../screens/cpf_input_screen.dart';
import '../screens/status/approved_screen.dart';
import '../screens/status/client_inactive_screen.dart';
import '../screens/status/client_not_found_screen.dart';
import '../screens/status/out_of_range_screen.dart';
import '../screens/status/recent_measurement_screen.dart';
import '../screens/status/status_message_screen.dart';
import '../screens/status/thank_you_screen.dart';
import '../services/erp_api_service.dart';

Future<void> navigateByErpResponse(
  BuildContext context,
  ErpResponse response, {
  required String deviceId,
  bool replace = true,
}) async {
  Widget destination;

  switch (response.message) {
    case 1:
      destination = const CpfInputScreen(
        mode: CpfInputMode.updateFaceThenMeasurement,
      );
      break;
    case 2:
      destination = const ClientNotFoundScreen();
      break;
    case 3:
      final clientId = response.clientId ?? response.patient?.id;
      final contractId = response.contractId;
      if (clientId == null || contractId == null) {
        destination = const ClientNotFoundScreen();
      } else {
        destination = BloodPressureInstructionScreen(
          patientId: clientId,
          contractId: contractId,
          deviceId: deviceId,
          nextInteractionAt: response.nextInteractionAt,
        );
      }
      break;
    case 4:
      destination = const ClientInactiveScreen();
      break;
    case 5:
      destination = const StatusMessageScreen(
        icon: Icons.check_circle_outline,
        iconColor: Color(0xFF1DB53F),
        title: 'Cliente ja aferiu',
        subtitle: 'Acesso liberado.',
      );
      break;
    case 6:
      destination = const RecentMeasurementScreen();
      break;
    case 7:  // Sistólica fora da normalidade
    case 14: // Diastólica fora da normalidade
    case 15: // BPM fora da normalidade
    case 16: // Aguardar Fisioterapeuta
      destination = const OutOfRangeScreen();
      break;
    case 8:
      destination = const ApprovedScreen();
      break;
    case 9:
      destination = const ThankYouScreen();
      break;
    case 10:
      destination = const StatusMessageScreen(
        icon: Icons.error_outline_rounded,
        iconColor: Color(0xFFFFC857),
        title: 'Acao invalida',
      );
      break;
    case 11:
      destination = const StatusMessageScreen(
        icon: Icons.badge_outlined,
        iconColor: Color(0xFFFFC857),
        title: 'CPF obrigatorio',
      );
      break;
    case 12:
      destination = const StatusMessageScreen(
        icon: Icons.badge_outlined,
        iconColor: Color(0xFFFFC857),
        title: 'CPF invalido',
      );
      break;
    default:
      destination = const ClientNotFoundScreen();
  }

  final route = MaterialPageRoute(builder: (_) => destination);
  if (replace) {
    await Navigator.of(context).pushReplacement(route);
  } else {
    await Navigator.of(context).push(route);
  }
}
