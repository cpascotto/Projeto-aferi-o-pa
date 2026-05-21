import 'dart:async';

import 'package:flutter/material.dart';

import '../../navigation/root_navigation.dart';

/// Tela genérica de status/mensagem usando o mesmo estilo visual
/// das telas internas do app (fundo azul-escuro, texto branco grande).
///
/// Pode receber um título principal, um subtítulo opcional e um tempo
/// para retornar automaticamente à tela inicial.
class StatusMessageScreen extends StatefulWidget {
  const StatusMessageScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = Colors.white,
    this.backgroundColor = const Color(0xFF0D3E69),
    this.autoReturn = const Duration(seconds: 6),
    this.onReturn,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final Color backgroundColor;

  /// Se diferente de zero, retorna automaticamente à raiz após esse tempo.
  final Duration autoReturn;

  /// Callback custom (sobrepõe popToRootRoute).
  final VoidCallback? onReturn;

  @override
  State<StatusMessageScreen> createState() => _StatusMessageScreenState();
}

class _StatusMessageScreenState extends State<StatusMessageScreen> {
  Timer? _timer;
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoReturn > Duration.zero) {
      _timer = Timer(widget.autoReturn, _exit);
    }
  }

  void _exit() {
    if (_isLeaving || !mounted) return;
    _isLeaving = true;
    if (widget.onReturn != null) {
      widget.onReturn!();
    } else {
      popToRootRoute(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: widget.iconColor, size: 92),
                    const SizedBox(height: 28),
                  ],
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 22),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
