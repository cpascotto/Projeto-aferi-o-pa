import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DebugLogStorageService {
  static const String _fileName = 'mobile_debug_logs.json';

  File? _cachedFile;
  Future<void> _writeQueue = Future.value();

  Future<List<Map<String, dynamic>>> readLogs() async {
    await _writeQueue;
    final file = await _resolveFile();
    if (!await file.exists()) {
      return const [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  Future<int> appendLog(Map<String, dynamic> entry) async {
    return _enqueue(() async {
      final logs = await _readLogsUnsafe();
      final updatedLogs = [...logs, entry];
      await _writeLogs(updatedLogs);
      return updatedLogs.length;
    });
  }

  Future<int> countLogs() async {
    final logs = await readLogs();
    return logs.length;
  }

  Future<void> clearLogs() async {
    await _enqueue(() async {
      await _writeLogs(const []);
    });
  }

  Future<void> _writeLogs(List<Map<String, dynamic>> logs) async {
    final file = await _resolveFile();
    await file.writeAsString(jsonEncode(logs), flush: true);
  }

  Future<List<Map<String, dynamic>>> _readLogsUnsafe() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return const [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = _writeQueue.then((_) => operation());
    _writeQueue = completer.then<void>((_) {}, onError: (_, __) {});
    return completer;
  }

  Future<File> _resolveFile() async {
    final cached = _cachedFile;
    if (cached != null) {
      return cached;
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$_fileName');
    _cachedFile = file;
    return file;
  }
}
