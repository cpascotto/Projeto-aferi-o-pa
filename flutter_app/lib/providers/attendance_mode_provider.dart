import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tipo de atendimento escolhido na tela inicial.
///
/// - [inicio]: paciente chegou — faz a identificação e a aferição (N3).
/// - [fim]: paciente está saindo — faz a identificação normal, mas em vez
///   de aferir, finaliza o atendimento (F1).
enum AttendanceMode { inicio, fim }

/// Modo de atendimento ativo. Definido na [AttendanceModeScreen] (home)
/// e lido na [IdentificationScreen] para decidir o que fazer após
/// confirmar a identidade do paciente.
final attendanceModeProvider =
    StateProvider<AttendanceMode>((ref) => AttendanceMode.inicio);
