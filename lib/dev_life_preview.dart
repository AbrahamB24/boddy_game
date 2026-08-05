// A dev-only entry point for looking at the map's LIVE effects.
//
//   flutter run -d windows -t lib/dev_life_preview.dart
//
// The settlement view sits behind a Supabase login, which makes "does the smoke
// look right" an expensive question to ask. This runs the two painters
// (ChimneySmoke, LampGlow) over the real render, on the map's own ground
// colour, at both life size and 3x — the same pairing tool/preview_on_map.py
// uses, so the still and the moving version can be compared directly.
//
// It imports the SAME widgets the map does. A preview that reimplemented them
// would agree with the map only until one of the two changed, which is the
// failure mode this file exists to avoid.
import 'dart:io';

import 'package:flutter/material.dart';

import 'features/settlement/data/building_definitions.dart';
import 'features/settlement/widgets/building_life.dart';

/// Where the render lives. Not an asset: it is authored output, and copying it
/// into assets/ would mean remembering to copy it again after every render.
const String kRenderPath = 'docs/renders/breeding_hut.png';

void main() => runApp(const _LifePreviewApp());

class _LifePreviewApp extends StatelessWidget {
  const _LifePreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Building life preview',
    home: Scaffold(
      // The era-I ground the map paints, so the effects are judged against
      // what they will actually sit on.
      backgroundColor: const Color(0xFF3E6B45),
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            _Specimen(width: 256, label: 'life size · 256 px'),
            SizedBox(width: 48),
            _Specimen(width: 560, label: '2.2x'),
          ],
        ),
      ),
    ),
  );
}

class _Specimen extends StatelessWidget {
  final double width;
  final String label;

  const _Specimen({required this.width, required this.label});

  @override
  Widget build(BuildContext context) {
    final chimney = kChimneyAnchor['breeding_hut']!;
    final file = File(kRenderPath);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: width * 1.25,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (file.existsSync())
                Image.file(file, fit: BoxFit.contain)
              else
                const Center(
                  child: Text('render missing — run the Blender script',
                      style: TextStyle(color: Colors.white)),
                ),
              const LampGlow(phaseSeed: 7),
              ChimneySmoke(
                anchorX: chimney.$1,
                anchorY: chimney.$2,
                phaseSeed: 7,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
