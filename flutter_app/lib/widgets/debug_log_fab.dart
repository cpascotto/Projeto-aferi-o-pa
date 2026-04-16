import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/debug_log_provider.dart';

class DebugLogFab extends ConsumerWidget {
  const DebugLogFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(debugLogControllerProvider);
    final controller = ref.read(debugLogControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(right: 16, bottom: 16),
        child: Align(
          alignment: Alignment.bottomRight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              FloatingActionButton.small(
                heroTag: 'debug-log-fab',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Enviando logs para a API local...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  final message = await controller.sendPendingLogs();
                  if (!context.mounted) return;
                  messenger
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(content: Text(message)));
                },
                child: state.isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bug_report),
              ),
              if (state.pendingCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Text(
                      state.pendingCount > 99 ? '99+' : '${state.pendingCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
