import 'dart:async';

import 'package:flutter/material.dart';

/// Gesto oculto: 5 toques sobre [child] dentro de 3 segundos disparan
/// [onActivated] (D-07 — sin chrome visible, no ocupa espacio en la UI).
class HiddenTapGesture extends StatefulWidget {
  const HiddenTapGesture({
    super.key,
    required this.child,
    required this.onActivated,
  });

  final Widget child;
  final VoidCallback onActivated;

  @override
  State<HiddenTapGesture> createState() => _HiddenTapGestureState();
}

class _HiddenTapGestureState extends State<HiddenTapGesture> {
  static const _tapsRequired = 5;
  static const _window = Duration(seconds: 3);

  int _tapCount = 0;
  Timer? _resetTimer;

  void _handleTap() {
    _tapCount++;
    _resetTimer?.cancel();

    if (_tapCount >= _tapsRequired) {
      _tapCount = 0;
      widget.onActivated();
      return;
    }

    _resetTimer = Timer(_window, () => _tapCount = 0);
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}
