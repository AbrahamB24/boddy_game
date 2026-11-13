import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'avatar_spec.dart';

/// Stacks an avatar's layer pictures into ONE image and remembers it.
///
/// Lists (chat, friends, ranking) show many avatars, so each look is composed
/// once into a single picture instead of keeping a dozen tinted images alive
/// per row. The layer pictures themselves are shared by every avatar.
class AvatarComposer {
  AvatarComposer._();
  static final AvatarComposer instance = AvatarComposer._();

  final Map<String, Future<ui.Image?>> _layers = {};
  final LinkedHashMap<String, Future<ui.Image?>> _done = LinkedHashMap();
  static const int _keep = 96;

  static String _path(bool bust, AvatarLayerRef l) =>
      'assets/images/avatar/${bust ? 'bust' : 'full'}/${l.layer}/${l.id}.png';

  Future<ui.Image?> _layer(bool bust, AvatarLayerRef l) =>
      _layers.putIfAbsent(_path(bust, l), () async {
        try {
          final data = await rootBundle.load(_path(bust, l));
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          return frame.image;
        } catch (_) {
          return null; // a missing picture just leaves its layer out
        }
      });

  /// The composed picture (a square, [bust] = head and shoulders).
  Future<ui.Image?> compose(AvatarSpec spec, {bool bust = false}) {
    final key = '${bust ? 'b' : 'f'}${spec.key}';
    final hit = _done.remove(key);
    if (hit != null) {
      _done[key] = hit; // most recently used goes last
      return hit;
    }
    final made = _compose(spec, bust);
    _done[key] = made;
    while (_done.length > _keep) {
      _done.remove(_done.keys.first); // evicted images are left to the GC
    }
    return made;
  }

  Future<ui.Image?> _compose(AvatarSpec spec, bool bust) async {
    final refs = spec.layers();
    final imgs = await Future.wait([for (final r in refs) _layer(bust, r)]);
    ui.Image? first;
    for (final i in imgs) {
      if (i != null) {
        first = i;
        break;
      }
    }
    if (first == null) return null;
    final w = first.width, h = first.height;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    for (var i = 0; i < refs.length; i++) {
      final img = imgs[i];
      if (img == null) continue;
      final slot = refs[i].slot;
      final paint = Paint()..filterQuality = FilterQuality.none;
      if (slot != null) {
        final c = spec.colorOf(slot);
        // The grey layers are multiplied by the colour; x1.2 makes up for the
        // light grey they are rendered in (so white really is white).
        const gain = 1.2;
        paint.colorFilter = ColorFilter.matrix(<double>[
          (c.r * gain).clamp(0.0, 1.4), 0, 0, 0, 0, //
          0, (c.g * gain).clamp(0.0, 1.4), 0, 0, 0, //
          0, 0, (c.b * gain).clamp(0.0, 1.4), 0, 0, //
          0, 0, 0, 1, 0,
        ]);
      }
      canvas.drawImage(img, Offset.zero, paint);
    }
    final pic = rec.endRecording();
    return pic.toImage(w, h);
  }
}

/// The avatar as a picture of [size] x [size]. [bust] = head and shoulders (for
/// small spots), otherwise the whole figure.
class AvatarView extends StatefulWidget {
  final AvatarSpec spec;
  final double size;
  final bool bust;

  const AvatarView({
    super.key,
    required this.spec,
    this.size = 48,
    this.bust = false,
  });

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  ui.Image? _img;
  Object _token = Object();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AvatarView old) {
    super.didUpdateWidget(old);
    if (old.spec != widget.spec || old.bust != widget.bust) _load();
  }

  void _load() {
    final token = _token = Object();
    AvatarComposer.instance.compose(widget.spec, bust: widget.bust).then((i) {
      if (mounted && token == _token) setState(() => _img = i);
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: _img == null
        ? null
        : RawImage(
            image: _img,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
  );
}
