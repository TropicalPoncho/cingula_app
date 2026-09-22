import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cingula_app/domain/entities/obra.dart';
import 'package:cingula_app/domain/repositories/obra_repository.dart';
import 'package:cingula_app/presentation/pages/home/widgets/obra_section.dart';

class _FakeObraRepository implements ObraRepository {
  _FakeObraRepository(List<Obra> initial) : _obras = List.of(initial);

  final List<Obra> _obras;
  final List<String> createdNames = [];

  @override
  Future<List<Obra>> fetchAll() async => List.of(_obras);

  @override
  Future<Obra?> findByUuid(String uuid) async {
    for (final o in _obras) {
      if (o.uuid == uuid) return o;
    }
    return null;
  }

  @override
  Future<String> createDraft(String name) async {
    createdNames.add(name);
    final uuid = 'obra-${_obras.length + 1}';
    _obras.add(Obra(uuid: uuid, name: name));
    return uuid;
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('con 2 obras el desplegable muestra 3 opciones (Sin obra + las 2)', (tester) async {
    final repo = _FakeObraRepository([
      const Obra(uuid: 'a', name: 'Obra A'),
      const Obra(uuid: 'b', name: 'Obra B'),
    ]);

    await tester.pumpWidget(wrap(ObraSection(repository: repo, onObraSelected: (_) {})));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<String?>), findsOneWidget);
    // Cerrado, solo se ve el valor seleccionado; hay que abrir el menú para ver las 3 opciones.
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();

    expect(find.text('Sin obra (se crea una al grabar)'), findsWidgets);
    expect(find.text('Obra A'), findsWidgets);
    expect(find.text('Obra B'), findsWidgets);
  });

  testWidgets('escribir un nombre y tocar Crear obra llama a createDraft y deja la obra seleccionada', (tester) async {
    final repo = _FakeObraRepository([]);
    String? selected;

    await tester.pumpWidget(wrap(ObraSection(repository: repo, onObraSelected: (u) => selected = u)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Nueva obra');
    await tester.tap(find.text('Crear obra'));
    await tester.pumpAndSettle();

    expect(repo.createdNames, ['Nueva obra']);
    expect(selected, 'obra-1');
  });

  testWidgets('tocar Crear obra con el campo vacío no llama a createDraft y muestra un aviso', (tester) async {
    final repo = _FakeObraRepository([]);

    await tester.pumpWidget(wrap(ObraSection(repository: repo, onObraSelected: (_) {})));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Crear obra'));
    await tester.pump();

    expect(repo.createdNames, isEmpty);
    expect(find.text('Ingresa un nombre para la obra'), findsOneWidget);
  });

  testWidgets('elegir una obra dispara onObraSelected con su uuid', (tester) async {
    final repo = _FakeObraRepository([
      const Obra(uuid: 'a', name: 'Obra A'),
      const Obra(uuid: 'b', name: 'Obra B'),
    ]);
    String? selected;

    await tester.pumpWidget(wrap(ObraSection(repository: repo, onObraSelected: (u) => selected = u)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra B').last);
    await tester.pumpAndSettle();

    expect(selected, 'b');
  });

  testWidgets('elegir "Sin obra" dispara onObraSelected con null', (tester) async {
    final repo = _FakeObraRepository([const Obra(uuid: 'a', name: 'Obra A')]);
    String? selected = 'a';

    await tester.pumpWidget(wrap(ObraSection(repository: repo, selectedUuid: 'a', onObraSelected: (u) => selected = u)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin obra (se crea una al grabar)').last);
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });
}
