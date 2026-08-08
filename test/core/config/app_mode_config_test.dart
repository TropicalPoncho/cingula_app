import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cingula_app/core/config/app_mode_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppModeConfig.isDebugMode = true;
  });

  test('instalación nueva: default es modo debug', () async {
    SharedPreferences.setMockInitialValues({});
    await AppModeConfig.loadFromPrefs();
    expect(AppModeConfig.isDebugMode, isTrue);
  });

  test('valor persistido false se respeta', () async {
    SharedPreferences.setMockInitialValues({'app_isDebugMode': false});
    await AppModeConfig.loadFromPrefs();
    expect(AppModeConfig.isDebugMode, isFalse);
  });

  test('valor persistido true se respeta', () async {
    SharedPreferences.setMockInitialValues({'app_isDebugMode': true});
    await AppModeConfig.loadFromPrefs();
    expect(AppModeConfig.isDebugMode, isTrue);
  });

  test('round-trip: setDebugMode persiste el valor entre cargas', () async {
    SharedPreferences.setMockInitialValues({});
    await AppModeConfig.setDebugMode(false);
    expect(AppModeConfig.isDebugMode, isFalse);

    AppModeConfig.isDebugMode = true;
    await AppModeConfig.loadFromPrefs();
    expect(AppModeConfig.isDebugMode, isFalse);
  });
}
