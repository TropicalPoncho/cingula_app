import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_initializer.dart';
import 'core/di/service_locator.dart';
import 'presentation/notifiers/permission_notifier.dart';
import 'presentation/notifiers/playback_notifier.dart';
import 'presentation/pages/intro_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initializer = AppInitializer();
  await initializer.init();
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

