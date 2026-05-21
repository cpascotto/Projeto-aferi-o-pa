import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/blood_pressure_measurement.dart';

class BleDeviceInfo {
  const BleDeviceInfo({
    required this.name,
    required this.id,
    this.rssi,
  });

  factory BleDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    final name = (map['name'] ?? '').toString().trim();
    final id = (map['id'] ?? map['address'] ?? '').toString().trim();
    final rawRssi = map['rssi'];
    return BleDeviceInfo(
      name: name,
      id: id,
      rssi: rawRssi is int ? rawRssi : int.tryParse(rawRssi?.toString() ?? ''),
    );
  }

  final String name;
  final String id;
  final int? rssi;

  String get displayName => name.isNotEmpty ? name : 'Dispositivo sem nome';
  String get displayId => id.isNotEmpty ? id : 'ID indisponivel';
}

class BloodPressureBleService {
  BloodPressureBleService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
              'afericao_automatizada_mobile/blood_pressure_ble',
            );

  final MethodChannel _channel;

  static const String defaultDeviceName = 'BT-BPM BLE';
  static const String _deviceNamePrefKey = 'ble_target_device_name';
  static const String _deviceIdPrefKey = 'ble_target_device_id';

  // ── Aferição ────────────────────────────────────────────────

  Future<BloodPressureMeasurement> captureMeasurement() async {
    final target = await getSavedTargetDevice();
    if (target == null || target.id.isEmpty) {
      throw StateError(
        'Medidor Bluetooth nao configurado. Selecione o dispositivo na tela de administrador.',
      );
    }

    await applyTargetDevice();
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'captureMeasurement',
    );

    if (response == null) {
      throw Exception('Nenhum dado de afericao foi retornado pelo Bluetooth.');
    }

    return BloodPressureMeasurement.fromMap(response);
  }

  Future<void> stopCapture() async {
    await _channel.invokeMethod<void>('stopCapture');
  }

  // ── Bluetooth status ────────────────────────────────────────

  Future<bool> isBluetoothEnabled() async {
    final result = await _channel.invokeMethod<bool>('isBluetoothEnabled');
    return result ?? false;
  }

  Future<void> requestEnableBluetooth() async {
    await _channel.invokeMethod<void>('requestEnableBluetooth');
  }

  Future<bool> ensureBluetoothPermissions() async {
    final result = await _channel.invokeMethod<bool>(
      'ensureBluetoothPermissions',
    );
    return result ?? false;
  }

  // ── Dispositivo alvo ────────────────────────────────────────

  Future<BleDeviceInfo?> getSavedTargetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_deviceIdPrefKey)?.trim() ?? '';
    final name = prefs.getString(_deviceNamePrefKey)?.trim() ?? '';
    if (id.isEmpty && name.isEmpty) return null;
    return BleDeviceInfo(name: name, id: id);
  }

  Future<void> saveTargetDevice(BleDeviceInfo? device) async {
    final prefs = await SharedPreferences.getInstance();
    if (device == null) {
      await prefs.remove(_deviceNamePrefKey);
      await prefs.remove(_deviceIdPrefKey);
      return;
    }

    if (device.name.isEmpty) {
      await prefs.remove(_deviceNamePrefKey);
    } else {
      await prefs.setString(_deviceNamePrefKey, device.name);
    }

    if (device.id.isEmpty) {
      await prefs.remove(_deviceIdPrefKey);
    } else {
      await prefs.setString(_deviceIdPrefKey, device.id);
    }
  }

  Future<void> applyTargetDevice() async {
    final target = await getSavedTargetDevice();
    await _channel.invokeMethod<void>('setTargetDevice', {
      'name': target?.name ?? '',
      'id': target?.id ?? '',
    });
  }

  // ── Scan ────────────────────────────────────────────────────

  Future<List<BleDeviceInfo>> getBondedDevices() async {
    await ensureBluetoothPermissions();
    final raw = await _channel.invokeListMethod<Object>('getBondedDevices');
    return _parseDevices(raw);
  }

  Future<List<BleDeviceInfo>> scanDevices() async {
    await ensureBluetoothPermissions();
    final raw = await _channel.invokeListMethod<Object>('scanBluetoothDevices');
    return _parseDevices(raw);
  }

  List<BleDeviceInfo> _parseDevices(List<Object?>? raw) {
    if (raw == null) return [];
    final devices = <BleDeviceInfo>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is Map) {
        final device = BleDeviceInfo.fromMap(item);
        if (device.id.isEmpty && device.name.isEmpty) continue;
        final key = device.id.isNotEmpty ? device.id : device.name;
        if (seen.add(key)) devices.add(device);
      }
    }
    devices.sort((a, b) {
      final byName = a.displayName.compareTo(b.displayName);
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return devices;
  }
}
