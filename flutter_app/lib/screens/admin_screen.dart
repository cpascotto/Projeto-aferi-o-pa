import 'dart:async';

import 'package:flutter/material.dart';

import '../services/blood_pressure_ble_service.dart';
import '../services/equipment_settings_service.dart';
import '../services/totem_mode_controller.dart';
import 'admin_log_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final TotemModeController _totem = TotemModeController.instance;
  final BloodPressureBleService _bleService = BloodPressureBleService();
  final EquipmentSettingsService _equipment = EquipmentSettingsService();

  // ── Totem ──────────────────────────────────────────────────
  late bool _totemEnabled;

  // ── Bluetooth ─────────────────────────────────────────────
  BleDeviceInfo? _savedBleDevice;
  BleDeviceInfo? _selectedBleDevice;
  bool _isScanning = false;
  List<BleDeviceInfo> _scannedDevices = [];

  // ── Equipamento (ID_Unidade / ID_Medidor) ─────────────────
  final TextEditingController _unitIdCtrl = TextEditingController();
  final TextEditingController _deviceIdCtrl = TextEditingController();
  String _savedUnitId = '';
  String _savedDeviceId = '';

  // ── Geral ─────────────────────────────────────────────────
  bool _isDirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _totemEnabled = _totem.enabled.value;
    unawaited(_loadSavedDevice());
    unawaited(_loadEquipmentIds());
    _unitIdCtrl.addListener(() {
      setState(_recalcDirty);
    });
    _deviceIdCtrl.addListener(() {
      setState(_recalcDirty);
    });
  }

  @override
  void dispose() {
    _unitIdCtrl.dispose();
    _deviceIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEquipmentIds() async {
    final unit = await _equipment.getUnitId();
    final dev = await _equipment.getDeviceId();
    if (!mounted) return;
    setState(() {
      _savedUnitId = unit;
      _savedDeviceId = dev;
      _unitIdCtrl.text = unit;
      _deviceIdCtrl.text = dev;
    });
  }

  Future<void> _loadSavedDevice() async {
    final device = await _bleService.getSavedTargetDevice();
    if (!mounted) return;
    setState(() {
      _savedBleDevice = device;
      _selectedBleDevice = device;
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
        _deviceKey(_selectedBleDevice) != _deviceKey(_savedBleDevice) ||
        _unitIdCtrl.text.trim() != _savedUnitId ||
        _deviceIdCtrl.text.trim() != _savedDeviceId;
  }

  String _deviceKey(BleDeviceInfo? device) {
    if (device == null) return '';
    return '${device.id}|${device.name}';
  }

  void _onTotemChanged(bool value) {
    setState(() {
      _totemEnabled = value;
      _recalcDirty();
    });
  }

  void _onDeviceSelected(BleDeviceInfo device) {
    setState(() {
      _selectedBleDevice = device;
      _recalcDirty();
    });
  }

  void _resetDevice() {
    setState(() {
      _selectedBleDevice = null;
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
    await _bleService.saveTargetDevice(_selectedBleDevice);
    await _bleService.applyTargetDevice();

    final unit = _unitIdCtrl.text.trim();
    final dev = _deviceIdCtrl.text.trim();
    await _equipment.setUnitId(unit);
    await _equipment.setDeviceId(dev);

    if (!mounted) return;
    setState(() {
      _savedBleDevice = _selectedBleDevice;
      _savedUnitId = unit;
      _savedDeviceId = dev;
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
            selectedDevice: _selectedBleDevice,
            isScanning: _isScanning,
            scannedDevices: _scannedDevices,
            onScan: _scan,
            onDeviceSelected: _onDeviceSelected,
            onReset: _resetDevice,
          ),
          const SizedBox(height: 24),

          // ── Seção Identificação do equipamento ───────────────
          const _SectionHeader(label: 'Identificação do equipamento'),
          const SizedBox(height: 8),
          _EquipmentSection(
            unitController: _unitIdCtrl,
            deviceController: _deviceIdCtrl,
          ),
          const SizedBox(height: 24),

          // ── Seção Diagnóstico ─────────────────────────────────
          const _SectionHeader(label: 'Diagnóstico'),
          const SizedBox(height: 8),
          _DiagnosticSection(
            onViewLogs: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminLogScreen()),
            ),
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
    required this.selectedDevice,
    required this.isScanning,
    required this.scannedDevices,
    required this.onScan,
    required this.onDeviceSelected,
    required this.onReset,
  });

  final BleDeviceInfo? selectedDevice;
  final bool isScanning;
  final List<BleDeviceInfo> scannedDevices;
  final VoidCallback onScan;
  final ValueChanged<BleDeviceInfo> onDeviceSelected;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final hasFixedDevice = selectedDevice?.id.isNotEmpty == true;
    final title = selectedDevice?.displayName ?? 'Nenhum medidor fixado';
    final subtitle = hasFixedDevice
        ? 'ID: ${selectedDevice!.id}'
        : 'Selecione pelo scan para travar este totem em um aparelho.';

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
                        title,
                        style: TextStyle(
                          color: hasFixedDevice
                              ? const Color(0xFF07999B)
                              : const Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: hasFixedDevice
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
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
              (device) => _DeviceTile(
                device: device,
                isSelected: _isSameDevice(device, selectedDevice),
                onTap: () => onDeviceSelected(device),
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
          if (selectedDevice != null) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Remover medidor fixado',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isSameDevice(BleDeviceInfo device, BleDeviceInfo? selected) {
    if (selected == null) return false;
    if (device.id.isNotEmpty && selected.id.isNotEmpty) {
      return device.id == selected.id;
    }
    return device.name == selected.name;
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  final BleDeviceInfo device;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      'ID: ${device.displayId}',
      if (device.rssi != null) 'Sinal: ${device.rssi} dBm',
    ].join('  ');

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF07999B)
                          : const Color(0xFF334155),
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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

// ── Seção de identificação do equipamento ───────────────────

class _EquipmentSection extends StatelessWidget {
  const _EquipmentSection({
    required this.unitController,
    required this.deviceController,
  });

  final TextEditingController unitController;
  final TextEditingController deviceController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Esses identificadores são enviados em todas as chamadas para a API do ERP.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 14),
          _EquipmentField(
            label: 'ID Unidade',
            hint: 'Ex.: 1',
            controller: unitController,
          ),
          const SizedBox(height: 12),
          _EquipmentField(
            label: 'ID Medidor',
            hint: 'Ex.: TOTEM-01',
            controller: deviceController,
          ),
        ],
      ),
    );
  }
}

// ── Seção de diagnóstico ────────────────────────────────────

class _DiagnosticSection extends StatelessWidget {
  const _DiagnosticSection({required this.onViewLogs});

  final VoidCallback onViewLogs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: const Icon(
          Icons.terminal_rounded,
          color: Color(0xFF0D3E69),
        ),
        title: const Text(
          'Ver logs do dispositivo',
          style: TextStyle(
            color: Color(0xFF0D3E69),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: const Text(
          'Exibe todas as chamadas ao ERP, embeddings e erros capturados.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: Color(0xFF64748B),
        ),
        onTap: onViewLogs,
      ),
    );
  }
}

class _EquipmentField extends StatelessWidget {
  const _EquipmentField({
    required this.label,
    required this.hint,
    required this.controller,
  });

  final String label;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0D3E69),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF07999B), width: 1.5),
            ),
          ),
          style: const TextStyle(
            color: Color(0xFF0D3E69),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
