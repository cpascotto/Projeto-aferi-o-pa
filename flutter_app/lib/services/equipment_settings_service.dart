import 'package:shared_preferences/shared_preferences.dart';

/// Mantém os identificadores do totem usados pela API do ERP.
class EquipmentSettingsService {
  static const String _unitKey = 'equipment_unit_id';
  static const String _deviceKey = 'equipment_device_id';

  Future<String> getUnitId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_unitKey) ?? '';
  }

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceKey) ?? '';
  }

  Future<void> setUnitId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(_unitKey);
    } else {
      await prefs.setString(_unitKey, value);
    }
  }

  Future<void> setDeviceId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(_deviceKey);
    } else {
      await prefs.setString(_deviceKey, value);
    }
  }
}
