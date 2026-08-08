import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cingula_app/presentation/widgets/hidden_tap_gesture.dart';

void main() {
  Future<void> pumpWidget(WidgetTester tester, VoidCallback onActivated) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HiddenTapGesture(
            onActivated: onActivated,
            child: const Text('Cingula'),
          ),
        ),
      ),
    );
  }

  testWidgets('5 taps consecutivos activan el callback exactamente 1 vez', (tester) async {
    var callCount = 0;
    await pumpWidget(tester, () => callCount++);

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Cingula'));
      await tester.pump();
    }

    expect(callCount, 1);
  });

  testWidgets('4 taps consecutivos no activan el callback', (tester) async {
    var callCount = 0;
    await pumpWidget(tester, () => callCount++);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Cingula'));
      await tester.pump();
    }

    expect(callCount, 0);
  });

  testWidgets('taps espaciados más de 3 segundos no acumulan', (tester) async {
    var callCount = 0;
    await pumpWidget(tester, () => callCount++);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Cingula'));
      await tester.pump();
    }

    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.text('Cingula'));
    await tester.pump();

    expect(callCount, 0);
  });

  testWidgets('el contador se resetea tras activar, no queda cargado', (tester) async {
    var callCount = 0;
    await pumpWidget(tester, () => callCount++);

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Cingula'));
      await tester.pump();
    }
    expect(callCount, 1);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Cingula'));
      await tester.pump();
    }
    expect(callCount, 1);
  });

  testWidgets('renderiza el child tal cual', (tester) async {
    await pumpWidget(tester, () {});
    expect(find.text('Cingula'), findsOneWidget);
  });
}
