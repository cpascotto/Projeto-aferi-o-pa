String onlyCpfDigits(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '');
}

String formatCpfDigits(String value) {
  final digits = onlyCpfDigits(value);
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length && index < 11; index++) {
    if (index == 3 || index == 6) {
      buffer.write('.');
    } else if (index == 9) {
      buffer.write('-');
    }
    buffer.write(digits[index]);
  }

  return buffer.toString();
}

/// Valida o CPF aplicando os dígitos verificadores (módulo 11).
///
/// Rejeita:
/// - tamanho diferente de 11
/// - CPFs com todos os dígitos iguais (000..., 111..., 999...)
/// - dígitos verificadores inválidos
bool isValidCpf(String value) {
  final digits = onlyCpfDigits(value);
  if (digits.length != 11) return false;

  // CPFs com todos os dígitos iguais são inválidos.
  if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

  int sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(digits[i]) * (10 - i);
  }
  int firstCheck = 11 - (sum % 11);
  if (firstCheck >= 10) firstCheck = 0;
  if (firstCheck != int.parse(digits[9])) return false;

  sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += int.parse(digits[i]) * (11 - i);
  }
  int secondCheck = 11 - (sum % 11);
  if (secondCheck >= 10) secondCheck = 0;
  if (secondCheck != int.parse(digits[10])) return false;

  return true;
}
