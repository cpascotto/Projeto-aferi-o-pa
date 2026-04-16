import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/blood_pressure_measurement.dart';

class BloodPressureBleService {
  BloodPressureBleService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
              'afericao_automatizada_mobile/blood_pressure_ble',
            );

  final MethodChannel _channel;

  static const String defaultDeviceName = 'BT-BPM BLE';
  static const String _prefKey = 'ble_target_device_name';

  // ── Aferição ────────────────────────────────────────────────

  Future<BloodPressureMeasurement> captureMeasurement() async {
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

  // ── Dispositivo alvo ────────────────────────────────────────

  Future<String> getSavedDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? defaultDeviceName;
  }

  Future<void> saveDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == defaultDeviceName) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, name);
    }
  }

  Future<void> applyTargetDeviceName() async {
    final name = await getSavedDeviceName();
    await _channel.invokeMethod<void>('setTargetDeviceName', {'name': name});
  }

  // ── Scan ────────────────────────────────────────────────────

  Future<List<String>> getBondedDevices() async {
    final raw = await _channel.invokeListMethod<Object>('getBondedDevices');
    return _parseDeviceNames(raw);
  }

  Future<List<String>> scanDevices() async {
    final raw = await _channel.invokeListMethod<Object>('scanBluetoothDevices');
    return _parseDeviceNames(raw);
  }

  List<String> _parseDeviceNames(List<Object?>? raw) {
    if (raw == null) return [];
    final names = <String>{};
    for (final item in raw) {
      if (item is Map) {
        final name = item['name']?.toString() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
    }
    return names.toList()..sort();
  }
}
