import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation/app_route_observer.dart';
import 'screens/splash_screen.dart';
import 'services/blood_pressure_ble_service.dart';
import 'services/erp_settings_service.dart';
import 'services/totem_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErpSettingsService.instance.load();
  await TotemModeController.instance.load();
  await BloodPressureBleService().applyTargetDevice();
  runApp(const ProviderScope(child: IdentificationApp()));
}

class IdentificationApp extends StatefulWidget {
  const IdentificationApp({super.key});

  @override
  State<IdentificationApp> createState() => _IdentificationAppState();
}

class _IdentificationAppState extends State<IdentificationApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      TotemModeController.instance.reapply();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vincere',
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
