import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_services_provider.dart';
import 'camera_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapApp());
  }

  Future<void> _bootstrapApp() async {
    final embeddingService = ref.read(embeddingServiceProvider);
    final startedAt = DateTime.now();

    try {
      await embeddingService.warmup().timeout(const Duration(seconds: 12));
    } catch (_) {
      // Se o warmup falhar ou demorar demais, o app continua e tenta novamente sob demanda.
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remaining = const Duration(seconds: 2) - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Inicializando reconhecimento facial...'),
          ],
        ),
      ),
    );
  }
}
