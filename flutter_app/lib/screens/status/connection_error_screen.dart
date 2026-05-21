import 'package:flutter/material.dart';

import '../../navigation/root_navigation.dart';

/// Tela genérica de erro de comunicação com o servidor.
///
/// Mantém o estilo visual do app (fundo azul-escuro, ícone, mensagem)
/// e oferece dois caminhos:
/// - "Tentar novamente": chama [onRetry] (se fornecido).
/// - "Voltar": volta à tela inicial via popToRootRoute.
class ConnectionErrorScreen extends StatelessWidget {
  const ConnectionErrorScreen({
    super.key,
    this.title = 'Falha de comunicação',
    this.message =
        'Não foi possível falar com o servidor agora.\nVerifique a conexão e tente novamente.',
    this.detail,
    this.onRetry,
  });

  final String title;
  final String message;

  /// Mensagem técnica curta (opcional) para identificar a falha.
  final String? detail;

  /// Se fornecido, mostra botão "Tentar novamente". Se null, só mostra "Voltar".
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        backgroundColor: const Color(0xFF0D3E69),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(0xFFFFC857),
                  size: 96,
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ],
                const Spacer(flex: 3),
                if (onRetry != null)
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 26),
                      label: const Text(
                        'Tentar novamente',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF07999B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (onRetry != null) const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () => popToRootRoute(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Voltar para o início',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
