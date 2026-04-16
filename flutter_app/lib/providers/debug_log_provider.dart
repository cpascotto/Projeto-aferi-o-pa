import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_services_provider.dart';
import '../services/api_service.dart';
import '../services/debug_log_storage_service.dart';

class DebugLogState {
  const DebugLogState({
    this.pendingCount = 0,
    this.isSending = false,
  });

  final int pendingCount;
  final bool isSending;

  DebugLogState copyWith({
    int? pendingCount,
    bool? isSending,
  }) {
    return DebugLogState(
      pendingCount: pendingCount ?? this.pendingCount,
      isSending: isSending ?? this.isSending,
    );
  }
}

final debugLogStorageProvider = Provider<DebugLogStorageService>((ref) {
  return DebugLogStorageService();
});

final debugLogControllerProvider =
    StateNotifierProvider<DebugLogController, DebugLogState>((ref) {
  return DebugLogController(
    storage: ref.watch(debugLogStorageProvider),
    apiService: ref.watch(apiServiceProvider),
  );
});

class DebugLogController extends StateNotifier<DebugLogState> {
  DebugLogController({
    required DebugLogStorageService storage,
    required ApiService apiService,
  })  : _storage = storage,
        _apiService = apiService,
        super(const DebugLogState()) {
    _loadPendingCount();
    recordLog(
      'App aberto ou reaberto. Coleta local de logs disponivel.',
      source: 'app_lifecycle',
    );
  }

  final DebugLogStorageService _storage;
  final ApiService _apiService;

  Future<void> recordLog(
    String message, {
    String source = 'app',
    Map<String, dynamic>? context,
  }) async {
    final count = await _storage.appendLog({
      'timestamp': DateTime.now().toIso8601String(),
      'source': source,
      'message': message,
      if (context != null && context.isNotEmpty) 'context': context,
    });
    state = state.copyWith(pendingCount: count);
  }

  Future<String> sendPendingLogs() async {
    if (state.isSending) {
      return 'O envio de logs já está em andamento.';
    }

    await recordLog(
      'Usuario acionou envio manual dos logs.',
      source: 'debug_button',
    );
    final logs = await _storage.readLogs();
    if (logs.isEmpty) {
      state = state.copyWith(pendingCount: 0);
      return 'Não há logs pendentes para enviar.';
    }

    state = state.copyWith(isSending: true, pendingCount: logs.length);
    try {
      final uploadedCount = await _apiService.sendMobileDebugLogs(logs);
      await _storage.clearLogs();
      state = state.copyWith(isSending: false, pendingCount: 0);
      return '$uploadedCount log(s) enviados com sucesso.';
    } catch (error) {
      state = state.copyWith(isSending: false, pendingCount: logs.length);
      return 'Falha ao enviar logs: $error';
    }
  }

  Future<void> refreshPendingCount() async {
    await _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    final count = await _storage.countLogs();
    state = state.copyWith(pendingCount: count);
  }
}
