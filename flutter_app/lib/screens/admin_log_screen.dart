import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/debug_log_storage_service.dart';

class AdminLogScreen extends StatefulWidget {
  const AdminLogScreen({super.key});

  @override
  State<AdminLogScreen> createState() => _AdminLogScreenState();
}

class _AdminLogScreenState extends State<AdminLogScreen> {
  final DebugLogStorageService _storage = DebugLogStorageService();

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  String? _loadError;

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final logs = await _storage.readLogs();
      if (!mounted) return;
      setState(() {
        // Mais recentes no topo.
        _logs = logs.reversed.toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar logs'),
        content: const Text('Apagar todos os logs salvos no dispositivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Apagar',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _storage.clearLogs();
    await _loadLogs();
  }

  void _copyAll() {
    final text = _logs
        .map((e) =>
            '[${e['timestamp'] ?? ''}] [${e['source'] ?? ''}] ${e['message'] ?? ''}'
            '${e['context'] != null ? '\n  ${e['context']}' : ''}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copiados para a área de transferência.')),
    );
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter.isEmpty) return _logs;
    final q = _filter.toLowerCase();
    return _logs.where((e) {
      final msg = (e['message'] ?? '').toString().toLowerCase();
      final src = (e['source'] ?? '').toString().toLowerCase();
      return msg.contains(q) || src.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Logs do dispositivo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Atualizar',
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copiar todos',
            onPressed: _logs.isEmpty ? null : _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
            tooltip: 'Limpar logs',
            onPressed: _logs.isEmpty ? null : _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de filtro
          Container(
            color: const Color(0xFF161B22),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Filtrar logs...',
                hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8B949E), size: 20),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0D1117),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF07999B)),
                ),
              ),
            ),
          ),
          // Contador
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                Text(
                  '${filtered.length} entrada(s)',
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF30363D)),
          // Lista
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF07999B)),
                  )
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 40),
                              const SizedBox(height: 12),
                              const Text(
                                'Erro ao carregar logs',
                                style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _loadError!,
                                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontFamily: 'monospace'),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _loadLogs,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Tentar novamente'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              _filter.isEmpty ? 'Nenhum log registrado.' : 'Nenhum resultado.',
                              style: const TextStyle(color: Color(0xFF8B949E)),
                            ),
                          )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFF21262D)),
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          return _LogEntry(entry: entry);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry extends StatelessWidget {
  const _LogEntry({required this.entry});

  final Map<String, dynamic> entry;

  Color _sourceColor(String source) {
    switch (source) {
      case 'enrollment':
        return const Color(0xFF79C0FF);
      case 'identification':
        return const Color(0xFF7EE787);
      case 'erp':
        return const Color(0xFFFFD700);
      case 'error':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFF8B949E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = entry['timestamp']?.toString() ?? '';
    final source = entry['source']?.toString() ?? 'app';
    final message = entry['message']?.toString() ?? '';
    final ctx = entry['context'];

    // Formata timestamp curto: HH:mm:ss
    String shortTs = ts;
    try {
      final dt = DateTime.parse(ts).toLocal();
      shortTs =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                shortTs,
                style: const TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _sourceColor(source).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  source,
                  style: TextStyle(
                    color: _sourceColor(source),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            message,
            style: const TextStyle(
              color: Color(0xFFE6EDF3),
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
          if (ctx != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              ctx.toString(),
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
