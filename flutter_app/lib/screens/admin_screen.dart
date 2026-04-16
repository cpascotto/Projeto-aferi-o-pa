import 'dart:async';

import 'package:flutter/material.dart';

import '../services/blood_pressure_ble_service.dart';
import '../services/totem_mode_controller.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final TotemModeController _totem = TotemModeController.instance;
  final BloodPressureBleService _bleService = BloodPressureBleService();

  // ── Totem ──────────────────────────────────────────────────
  late bool _totemEnabled;

  // ── Bluetooth ─────────────────────────────────────────────
  String _savedDeviceName = BloodPressureBleService.defaultDeviceName;
  String _selectedDeviceName = BloodPressureBleService.defaultDeviceName;
  bool _isScanning = false;
  List<String> _scannedDevices = [];

  // ── Geral ─────────────────────────────────────────────────
  bool _isDirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _totemEnabled = _totem.enabled.value;
    unawaited(_loadSavedDevice());
  }

  Future<void> _loadSavedDevice() async {
    final name = await _bleService.getSavedDeviceName();
    if (!mounted) return;
    setState(() {
      _savedDeviceName = name;
      _selectedDeviceName = name;
    });
    unawaited(_loadBondedDevices());
  }

  Future<void> _loadBondedDevices() async {
    try {
      final devices = await _bleService.getBondedDevices();
      if (!mounted) return;
      setState(() {
        _scannedDevices = devices;
      });
    } catch (_) {}
  }

  void _recalcDirty() {
    _isDirty = _totemEnabled != _totem.enabled.value ||
        _selectedDeviceName != _savedDeviceName;
  }

  void _onTotemChanged(bool value) {
    setState(() {
      _totemEnabled = value;
      _recalcDirty();
    });
  }

  void _onDeviceSelected(String name) {
    setState(() {
      _selectedDeviceName = name;
      _recalcDirty();
    });
  }

  void _resetDevice() {
    setState(() {
      _selectedDeviceName = BloodPressureBleService.defaultDeviceName;
      _recalcDirty();
    });
  }

  Future<void> _scan() async {
    setState(() {
      _isScanning = true;
      _scannedDevices = [];
    });
    try {
      final devices = await _bleService.scanDevices();
      if (!mounted) return;
      setState(() => _scannedDevices = devices);
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    await _totem.setEnabled(_totemEnabled);
    await _bleService.saveDeviceName(_selectedDeviceName);
    await _bleService.applyTargetDeviceName();

    if (!mounted) return;
    setState(() {
      _savedDeviceName = _selectedDeviceName;
      _isDirty = false;
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configurações salvas.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'Administrador',
          style: TextStyle(
            color: Color(0xFF0D3E69),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0D3E69)),
        actions: [
          if (_isDirty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Salvar',
                        style: TextStyle(
                          color: Color(0xFF07999B),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ── Seção totem ─────────────────────────────────────
          const _SectionHeader(label: 'Modo de exibição'),
          _SettingTile(
            title: 'Modo totem',
            subtitle:
                'Mantém o app em tela cheia e impede o celular de apagar a tela.',
            value: _totemEnabled,
            onChanged: _onTotemChanged,
          ),
          const SizedBox(height: 24),

          // ── Seção Bluetooth ──────────────────────────────────
          const _SectionHeader(label: 'Dispositivo Bluetooth'),
          const SizedBox(height: 8),
          _DeviceSection(
            savedDeviceName: _savedDeviceName,
            selectedDeviceName: _selectedDeviceName,
            isScanning: _isScanning,
            scannedDevices: _scannedDevices,
            onScan: _scan,
            onDeviceSelected: _onDeviceSelected,
            onReset: _resetDevice,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Seção de dispositivo BLE ────────────────────────────────

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.savedDeviceName,
    required this.selectedDeviceName,
    required this.isScanning,
    required this.scannedDevices,
    required this.onScan,
    required this.onDeviceSelected,
    required this.onReset,
  });

  final String savedDeviceName;
  final String selectedDeviceName;
  final bool isScanning;
  final List<String> scannedDevices;
  final VoidCallback onScan;
  final ValueChanged<String> onDeviceSelected;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final isDefault =
        selectedDeviceName == BloodPressureBleService.defaultDeviceName;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho com dispositivo atual e botão scan
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dispositivo selecionado',
                        style: TextStyle(
                          color: Color(0xFF0D3E69),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedDeviceName,
                        style: TextStyle(
                          color: isDefault
                              ? const Color(0xFF64748B)
                              : const Color(0xFF07999B),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Botão procurar
                SizedBox(
                  height: 38,
                  child: TextButton.icon(
                    onPressed: isScanning ? null : onScan,
                    icon: isScanning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(isScanning ? 'Procurando...' : 'Procurar'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0D3E69),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isScanning)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Procurando dispositivos BLE próximos, aguarde ~5s...',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            )
          else if (scannedDevices.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            ...scannedDevices.map(
              (name) => _DeviceTile(
                name: name,
                isSelected: name == selectedDeviceName,
                onTap: () => onDeviceSelected(name),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Nenhum dispositivo pareado encontrado. Toque em Procurar com o aparelho ligado e próximo.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ),

          // Botão restaurar padrão
          if (!isDefault) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Restaurar padrão (${BloodPressureBleService.defaultDeviceName})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: isSelected
                  ? const Color(0xFF07999B)
                  : const Color(0xFFCBD5E1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF07999B)
                      : const Color(0xFF334155),
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets base ────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0D3E69),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
        ),
        value: value,
        activeThumbColor: const Color(0xFF07999B),
        onChanged: onChanged,
      ),
    );
  }
}
