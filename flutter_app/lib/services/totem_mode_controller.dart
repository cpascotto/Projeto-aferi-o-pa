import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TotemModeController {
  TotemModeController._();

  static final TotemModeController instance = TotemModeController._();

  static const MethodChannel _channel = MethodChannel(
    'afericao_automatizada_mobile/totem_mode',
  );

  static const String _prefKey = 'totem_mode_enabled';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_prefKey) ?? true;
    enabled.value = value;
    await _apply(value);
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    await _apply(value);
  }

  Future<void> reapply() async {
    await _apply(enabled.value);
  }

  Future<void> _apply(bool value) async {
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    try {
      await _channel.invokeMethod<void>(
        'setKeepScreenOn',
        <String, bool>{'enabled': value},
      );
    } on MissingPluginException {
      return;
    }
  }
}
