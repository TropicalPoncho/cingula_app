import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_initializer.dart';
import 'core/di/service_locator.dart';
import 'presentation/notifiers/permission_notifier.dart';
import 'presentation/notifiers/playback_notifier.dart';
import 'presentation/pages/intro_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Wrap initialization in try-catch to prevent crashes during startup
  try {
    final initializer = AppInitializer();
    await initializer.init();
    
    // TEMPORARILY DISABLED: Auto-start of poller to diagnose crash
    // You can enable it manually from UI once app is stable
    // final poller = BackgroundAdaptivePoller(
    //   monitorUseCase: getIt<MonitorUserLocationUseCase>(),
    //   triggerRepository: getIt<GeoTriggerRepository>(),
    //   locationRepository: getIt<LocationRepository>(),
    //   onLog: (m) => debugPrint('[poller] $m'),
    // );
    // if (!getIt.isRegistered<BackgroundAdaptivePoller>()) {
    //   getIt.registerSingleton<BackgroundAdaptivePoller>(poller);
    // }
    // poller.start();
  } catch (e, st) {
    debugPrint('ERROR during app initialization: $e');
    debugPrint('Stack trace: $st');
  }
  
  runApp(const CingulaApp());
}

class CingulaApp extends StatelessWidget {
  const CingulaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Verificamos permisos al arranque para informar al usuario.
        ChangeNotifierProvider(
          create: (_) => PermissionNotifier(
            locationRepository: getIt(),
          ),
        ),
        // Notifier que controla la reproducción según geolocalización.
        ChangeNotifierProvider(
          create: (_) => PlaybackNotifier(
            monitorUseCase: getIt(),
            logService: getIt(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Cingula',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const IntroPage(),
      ),
    );
  }
}

