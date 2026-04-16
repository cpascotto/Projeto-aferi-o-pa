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
