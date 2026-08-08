import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cingula_app/domain/entities/audio_asset.dart';
import 'package:cingula_app/presentation/pages/home/widgets/audio_details.dart';
import 'package:cingula_app/presentation/pages/home/widgets/user_mode_view.dart';

void main() {
  const asset = AudioAsset(
    id: 1,
    title: 'Chelenko',
    artist: 'Cingula',
    description: 'Test',
    duration: Duration(minutes: 3),
    localPath: 'assets/audio/Chelenko.mp3',
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('sin monitoreo, sin status, sin audio: muestra "Listo para iniciar"', (tester) async {
    await tester.pumpWidget(wrap(UserModeView(
      isMonitoring: false,
      statusMessage: null,
      currentAsset: null,
      onMonitoringChanged: (_) {},
    )));

    expect(find.text('Listo para iniciar'), findsOneWidget);
  });

  testWidgets('monitoreando sin status: muestra el copy por defecto de caminata', (tester) async {
    await tester.pumpWidget(wrap(UserModeView(
      isMonitoring: true,
      statusMessage: null,
      currentAsset: null,
      onMonitoringChanged: (_) {},
    )));

    expect(
      find.text('Caminando… te avisamos cuando estés cerca de un punto sonoro.'),
      findsOneWidget,
    );
  });

  testWidgets('statusMessage explícito gana sobre el copy por defecto', (tester) async {
    await tester.pumpWidget(wrap(UserModeView(
      isMonitoring: true,
      statusMessage: 'Monitoreo activo',
      currentAsset: null,
      onMonitoringChanged: (_) {},
    )));

    expect(find.text('Monitoreo activo'), findsOneWidget);
  });

  testWidgets('sin currentAsset no renderiza AudioDetails', (tester) async {
    await tester.pumpWidget(wrap(UserModeView(
      isMonitoring: false,
      statusMessage: null,
      currentAsset: null,
      onMonitoringChanged: (_) {},
    )));

    expect(find.byType(AudioDetails), findsNothing);
  });

  testWidgets('con currentAsset renderiza AudioDetails con el título', (tester) async {
    await tester.pumpWidget(wrap(UserModeView(
      isMonitoring: false,
      statusMessage: null,
      currentAsset: asset,
      onMonitoringChanged: (_) {},
    )));

    expect(find.byType(AudioDetails), findsOneWidget);
    expect(find.text('Chelenko'), findsOneWidget);
  });

  testWidgets('tocar el switch invoca onMonitoringChanged con el valor negado', (tester) async {
    bool? received;
    await tester.pumpWidget(wrap(UserModeView(
      isMonitoring: false,
      statusMessage: null,
      currentAsset: null,
      onMonitoringChanged: (v) => received = v,
    )));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(received, isTrue);
  });
}
