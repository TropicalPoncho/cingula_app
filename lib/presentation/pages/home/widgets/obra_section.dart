import 'package:flutter/material.dart';

import '../../../../domain/entities/obra.dart';
import '../../../../domain/repositories/obra_repository.dart';

/// Sección "Obra" del panel de debug (D-22): nombre + crear + elegir, mismo
/// patrón que tenía la vieja sección Región. El repositorio entra por
/// parámetro (no se resuelve internamente vía service locator) para que el
/// widget test lo pueda reemplazar sin montar todo el árbol de dependencias.
class ObraSection extends StatefulWidget {
  const ObraSection({required this.repository, required this.onObraSelected, this.selectedUuid, super.key});

  final ObraRepository repository;
  final void Function(String? obraUuid) onObraSelected;
  final String? selectedUuid;

  @override
  State<ObraSection> createState() => _ObraSectionState();
}

class _ObraSectionState extends State<ObraSection> {
  List<Obra> _obras = [];
  final TextEditingController _nameController = TextEditingController(text: 'Mi obra');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final obras = await widget.repository.fetchAll();
    if (mounted) setState(() => _obras = obras);
  }

  Future<void> _createObra() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un nombre para la obra')),
      );
      return;
    }
    final uuid = await widget.repository.createDraft(name);
    await _load();
    widget.onObraSelected(uuid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Obra «$name» creada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Panel: Obra'),
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Nombre de la obra',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: _createObra,
            icon: const Icon(Icons.library_music),
            label: const Text('Crear obra'),
          ),
        ),
        const SizedBox(height: 12),
        if (_obras.isEmpty)
          Text(
            'No hay obras. Creá una arriba o grabá sin elegir: se crea sola.',
            style: TextStyle(color: Colors.grey[600]),
          )
        else
          DropdownButton<String?>(
            value: widget.selectedUuid,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Sin obra (se crea una al grabar)')),
              ..._obras.map((o) => DropdownMenuItem<String?>(value: o.uuid, child: Text(o.name))),
            ],
            onChanged: widget.onObraSelected,
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
