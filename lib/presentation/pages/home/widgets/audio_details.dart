import '../../../../domain/entities/audio_asset.dart';
import 'package:flutter/material.dart';

class AudioDetails extends StatelessWidget {
  final AudioAsset asset;
  const AudioDetails({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(asset.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(asset.description),
          ],
        ),
      ),
    );
  }
}
