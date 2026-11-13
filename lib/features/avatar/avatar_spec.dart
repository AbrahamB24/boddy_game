import 'dart:math';
import 'dart:ui' show Color;

import 'avatar_catalog.dart';
import 'avatar_layers.g.dart';

/// One player's avatar: which part per category and which colour per slot.
/// Stored as a small JSON object in `profiles.avatar` (migration 0070), so a
/// part that is dropped or renamed later falls back to a default instead of
/// breaking anyone's picture.
class AvatarSpec {
  final String hair, eyes, mouth, beard, top, bottom, shoes, hat, extra;
  final int hairC, eyesC, skinC, topC, top2C, bottomC, shoesC, hatC, extraC;

  const AvatarSpec({
    this.hair = 'short',
    this.eyes = 'round',
    this.mouth = 'smile',
    this.beard = 'none',
    this.top = 'tunic',
    this.bottom = 'trousers',
    this.shoes = 'boots',
    this.hat = 'none',
    this.extra = 'none',
    this.hairC = 1,
    this.eyesC = 1,
    this.skinC = 2,
    this.topC = 0,
    this.top2C = 2,
    this.bottomC = 7,
    this.shoesC = 10,
    this.hatC = 4,
    this.extraC = 3,
  });

  static const defaults = AvatarSpec();

  String partOf(AvatarCategory c) => switch (c) {
    AvatarCategory.hair => hair,
    AvatarCategory.eyes => eyes,
    AvatarCategory.mouth => mouth,
    AvatarCategory.beard => beard,
    AvatarCategory.skin => 'base',
    AvatarCategory.top => top,
    AvatarCategory.bottom => bottom,
    AvatarCategory.shoes => shoes,
    AvatarCategory.hat => hat,
    AvatarCategory.extra => extra,
  };

  int colorIndex(AvatarSlot s) => switch (s) {
    AvatarSlot.skin => skinC,
    AvatarSlot.hair => hairC,
    AvatarSlot.eyes => eyesC,
    AvatarSlot.top => topC,
    AvatarSlot.top2 => top2C,
    AvatarSlot.bottom => bottomC,
    AvatarSlot.shoes => shoesC,
    AvatarSlot.hat => hatC,
    AvatarSlot.acc => extraC,
  };

  Color colorOf(AvatarSlot s) {
    final p = paletteFor(s);
    return p[colorIndex(s).clamp(0, p.length - 1)];
  }

  AvatarSpec withPart(AvatarCategory c, String id) => _copy(
    hair: c == AvatarCategory.hair ? id : null,
    eyes: c == AvatarCategory.eyes ? id : null,
    mouth: c == AvatarCategory.mouth ? id : null,
    beard: c == AvatarCategory.beard ? id : null,
    top: c == AvatarCategory.top ? id : null,
    bottom: c == AvatarCategory.bottom ? id : null,
    shoes: c == AvatarCategory.shoes ? id : null,
    hat: c == AvatarCategory.hat ? id : null,
    extra: c == AvatarCategory.extra ? id : null,
  );

  AvatarSpec withColor(AvatarSlot s, int i) => _copy(
    hairC: s == AvatarSlot.hair ? i : null,
    eyesC: s == AvatarSlot.eyes ? i : null,
    skinC: s == AvatarSlot.skin ? i : null,
    topC: s == AvatarSlot.top ? i : null,
    top2C: s == AvatarSlot.top2 ? i : null,
    bottomC: s == AvatarSlot.bottom ? i : null,
    shoesC: s == AvatarSlot.shoes ? i : null,
    hatC: s == AvatarSlot.hat ? i : null,
    extraC: s == AvatarSlot.acc ? i : null,
  );

  AvatarSpec _copy({
    String? hair,
    String? eyes,
    String? mouth,
    String? beard,
    String? top,
    String? bottom,
    String? shoes,
    String? hat,
    String? extra,
    int? hairC,
    int? eyesC,
    int? skinC,
    int? topC,
    int? top2C,
    int? bottomC,
    int? shoesC,
    int? hatC,
    int? extraC,
  }) => AvatarSpec(
    hair: hair ?? this.hair,
    eyes: eyes ?? this.eyes,
    mouth: mouth ?? this.mouth,
    beard: beard ?? this.beard,
    top: top ?? this.top,
    bottom: bottom ?? this.bottom,
    shoes: shoes ?? this.shoes,
    hat: hat ?? this.hat,
    extra: extra ?? this.extra,
    hairC: hairC ?? this.hairC,
    eyesC: eyesC ?? this.eyesC,
    skinC: skinC ?? this.skinC,
    topC: topC ?? this.topC,
    top2C: top2C ?? this.top2C,
    bottomC: bottomC ?? this.bottomC,
    shoesC: shoesC ?? this.shoesC,
    hatC: hatC ?? this.hatC,
    extraC: extraC ?? this.extraC,
  );

  Map<String, dynamic> toJson() => {
    'v': 1,
    'hair': hair,
    'eyes': eyes,
    'mouth': mouth,
    'beard': beard,
    'top': top,
    'bottom': bottom,
    'shoes': shoes,
    'hat': hat,
    'extra': extra,
    'hairC': hairC,
    'eyesC': eyesC,
    'skinC': skinC,
    'topC': topC,
    'top2C': top2C,
    'bottomC': bottomC,
    'shoesC': shoesC,
    'hatC': hatC,
    'extraC': extraC,
  };

  /// Tolerant: anything missing, unknown or out of range becomes the default.
  factory AvatarSpec.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    const d = defaults;
    String part(AvatarCategory c, String key, String fallback) {
      final v = raw[key];
      return v is String && partFor(c, v) != null ? v : fallback;
    }

    int col(String key, AvatarSlot s, int fallback) {
      final v = raw[key];
      final n = paletteFor(s).length;
      return v is int && v >= 0 && v < n ? v : fallback;
    }

    return AvatarSpec(
      hair: part(AvatarCategory.hair, 'hair', d.hair),
      eyes: part(AvatarCategory.eyes, 'eyes', d.eyes),
      mouth: part(AvatarCategory.mouth, 'mouth', d.mouth),
      beard: part(AvatarCategory.beard, 'beard', d.beard),
      top: part(AvatarCategory.top, 'top', d.top),
      bottom: part(AvatarCategory.bottom, 'bottom', d.bottom),
      shoes: part(AvatarCategory.shoes, 'shoes', d.shoes),
      hat: part(AvatarCategory.hat, 'hat', d.hat),
      extra: part(AvatarCategory.extra, 'extra', d.extra),
      hairC: col('hairC', AvatarSlot.hair, d.hairC),
      eyesC: col('eyesC', AvatarSlot.eyes, d.eyesC),
      skinC: col('skinC', AvatarSlot.skin, d.skinC),
      topC: col('topC', AvatarSlot.top, d.topC),
      top2C: col('top2C', AvatarSlot.top2, d.top2C),
      bottomC: col('bottomC', AvatarSlot.bottom, d.bottomC),
      shoesC: col('shoesC', AvatarSlot.shoes, d.shoesC),
      hatC: col('hatC', AvatarSlot.hat, d.hatC),
      extraC: col('extraC', AvatarSlot.acc, d.extraC),
    );
  }

  /// A random but only unlocked look.
  factory AvatarSpec.random(AvatarProgress progress, [Random? rng]) {
    final r = rng ?? Random();
    var s = const AvatarSpec();
    for (final c in AvatarCategory.values) {
      final open = [
        for (final p in kParts[c] ?? const <AvatarPart>[])
          if (p.unlock.isMet(progress)) p,
      ];
      if (open.isNotEmpty) s = s.withPart(c, open[r.nextInt(open.length)].id);
    }
    for (final slot in AvatarSlot.values) {
      s = s.withColor(slot, r.nextInt(paletteFor(slot).length));
    }
    // A hat on one look in three, an accessory on one in four.
    if (r.nextInt(3) != 0) s = s.withPart(AvatarCategory.hat, 'none');
    if (r.nextInt(4) != 0) s = s.withPart(AvatarCategory.extra, 'none');
    if (r.nextInt(3) != 0) s = s.withPart(AvatarCategory.beard, 'none');
    return s;
  }

  /// The pictures to stack for this look, back to front: layer name + part id
  /// (only those that exist) and the slot that tints each.
  List<AvatarLayerRef> layers() {
    final out = <AvatarLayerRef>[];
    void add(String layer, String id) {
      if (id == 'none') return;
      if (!kAvatarLayerFiles.contains('$layer/$id')) return;
      out.add(AvatarLayerRef(layer, id));
    }

    for (final l in kLayers) {
      final id = switch (l.name) {
        'body' || 'head' => 'base',
        'acc_back' || 'acc_front' => extra,
        'hair_back' || 'hair_front' => hair,
        'eyes_white' || 'eyes' || 'brows' => eyes,
        'beard' => beard,
        'mouth' => mouth,
        'top' || 'top_trim' => top,
        'bottom' => bottom,
        'shoes' => shoes,
        'hat' || 'hat_trim' => hat,
        _ => 'none',
      };
      add(l.name, id);
    }
    return out;
  }

  String get key => toJson().values.join('|');

  @override
  bool operator ==(Object other) => other is AvatarSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class AvatarLayerRef {
  final String layer;
  final String id;
  const AvatarLayerRef(this.layer, this.id);

  AvatarSlot? get slot {
    for (final l in kLayers) {
      if (l.name == layer) return l.slot;
    }
    return null;
  }
}
