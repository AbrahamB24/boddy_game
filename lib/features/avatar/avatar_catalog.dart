import 'package:flutter/painting.dart';

import '../guild/guild_service.dart';
import '../settlement/settlement_controller.dart';

// The avatar's parts (user 2026-11-13: "Avatarcreator" — voxel figure, layers).
//
// The art is rendered by tool/blender/avatar.py as one transparent picture per
// part, all with the same camera; the app stacks them and tints the grey ones.
// The ids below are the ids of those files (assets/images/avatar/<view>/<layer>/<id>.png).
// Which files really exist is in avatar_layers.g.dart (written from the render
// folder), so a part without a file for some layer (bald has no hair) is skipped.

/// One colour choice per slot; each slot tints the layers named in [kLayers].
enum AvatarSlot { skin, hair, eyes, top, top2, bottom, shoes, hat, acc }

/// A layer of the stack, back to front. [slot] null = fixed colours.
class AvatarLayer {
  final String name;
  final AvatarSlot? slot;
  const AvatarLayer(this.name, this.slot);
}

/// Back to front. 'body' and 'head' are the figure itself (id 'base').
const List<AvatarLayer> kLayers = [
  AvatarLayer('acc_back', AvatarSlot.acc),
  AvatarLayer('hair_back', AvatarSlot.hair),
  AvatarLayer('body', AvatarSlot.skin),
  AvatarLayer('bottom', AvatarSlot.bottom),
  AvatarLayer('shoes', AvatarSlot.shoes),
  AvatarLayer('top', AvatarSlot.top),
  AvatarLayer('top_trim', AvatarSlot.top2),
  AvatarLayer('head', AvatarSlot.skin),
  AvatarLayer('eyes_white', null),
  AvatarLayer('eyes', AvatarSlot.eyes),
  AvatarLayer('brows', AvatarSlot.hair),
  AvatarLayer('beard', AvatarSlot.hair),
  AvatarLayer('mouth', null),
  AvatarLayer('hair_front', AvatarSlot.hair),
  AvatarLayer('hat', AvatarSlot.hat),
  AvatarLayer('hat_trim', AvatarSlot.top2),
  AvatarLayer('acc_front', AvatarSlot.acc),
];

// ── colours ──────────────────────────────────────────────────────────────

const List<Color> kSkinTones = [
  Color(0xFFFDE0C8),
  Color(0xFFF5CBA7),
  Color(0xFFE8B890),
  Color(0xFFD9A070),
  Color(0xFFC68A62),
  Color(0xFFA86A48),
  Color(0xFF7D4A32),
  Color(0xFF5A3424),
];

const List<Color> kHairColors = [
  Color(0xFF2A2220),
  Color(0xFF4A3020),
  Color(0xFF6E4A2C),
  Color(0xFF8A3A22),
  Color(0xFFC0501E),
  Color(0xFFD8A838),
  Color(0xFFECDCA0),
  Color(0xFF9A9A9A),
  Color(0xFFE8E8E8),
  Color(0xFF3A6AC8),
  Color(0xFFD86AA0),
  Color(0xFF3A9A5A),
];

const List<Color> kEyeColors = [
  Color(0xFF6A4020),
  Color(0xFF3A7AC0),
  Color(0xFF3A8A4A),
  Color(0xFF6A7A88),
  Color(0xFF7A4AB8),
  Color(0xFFC08A20),
  Color(0xFF202020),
  Color(0xFFC03A3A),
];

const List<Color> kClothColors = [
  Color(0xFFC0392B),
  Color(0xFFE67E22),
  Color(0xFFF2C340),
  Color(0xFF8DBE3C),
  Color(0xFF2E7D4F),
  Color(0xFF3AA6A0),
  Color(0xFF3A6AC8),
  Color(0xFF2A3F8A),
  Color(0xFF7A4AB8),
  Color(0xFFD86AA0),
  Color(0xFF6A4A30),
  Color(0xFFF0E6D0),
  Color(0xFF9AA4AE),
  Color(0xFF5A6470),
  Color(0xFF2A2F38),
  Color(0xFFFFFFFF),
];

List<Color> paletteFor(AvatarSlot s) => switch (s) {
  AvatarSlot.skin => kSkinTones,
  AvatarSlot.hair => kHairColors,
  AvatarSlot.eyes => kEyeColors,
  _ => kClothColors,
};

// ── unlocks ──────────────────────────────────────────────────────────────

/// What the player has reached; read from the game when the creator opens.
class AvatarProgress {
  final int battles;
  final int stars;
  final int floor;
  final bool inGuild;
  const AvatarProgress({
    this.battles = 0,
    this.stars = 0,
    this.floor = 0,
    this.inGuild = false,
  });

  factory AvatarProgress.current() {
    final s = SettlementController();
    return AvatarProgress(
      battles: s.battlesCleared,
      stars: s.totalStars,
      floor: s.survivalBestFloor,
      inGuild: GuildMembership.instance.inGuild,
    );
  }

  /// Everything open (a dev build, or a viewer who only looks).
  static const all = AvatarProgress(
    battles: 1 << 20,
    stars: 1 << 20,
    floor: 1 << 20,
    inGuild: true,
  );
}

class AvatarUnlock {
  final int battles;
  final int stars;
  final int floor;
  final bool guild;
  const AvatarUnlock({
    this.battles = 0,
    this.stars = 0,
    this.floor = 0,
    this.guild = false,
  });

  static const free = AvatarUnlock();

  bool isMet(AvatarProgress p) =>
      p.battles >= battles &&
      p.stars >= stars &&
      p.floor >= floor &&
      (!guild || p.inGuild);

  /// The hint the creator prints under a locked part.
  String get hint {
    final bits = <String>[
      if (battles > 0) 'clear $battles battles',
      if (stars > 0) 'collect $stars stars',
      if (floor > 0) 'reach Survival floor $floor',
      if (guild) 'join a guild',
    ];
    return bits.isEmpty ? '' : 'Unlock: ${bits.join(' and ')}';
  }
}

// ── parts ────────────────────────────────────────────────────────────────

class AvatarPart {
  final String id;
  final String name;
  final AvatarUnlock unlock;
  const AvatarPart(this.id, this.name, [this.unlock = AvatarUnlock.free]);
}

/// A tab of the creator: the parts to choose from and which colours belong.
enum AvatarCategory {
  hair('Hair', [AvatarSlot.hair]),
  eyes('Eyes', [AvatarSlot.eyes]),
  mouth('Mouth', []),
  beard('Beard', [AvatarSlot.hair]),
  skin('Skin', [AvatarSlot.skin]),
  top('Top', [AvatarSlot.top, AvatarSlot.top2]),
  bottom('Bottom', [AvatarSlot.bottom]),
  shoes('Shoes', [AvatarSlot.shoes]),
  hat('Hat', [AvatarSlot.hat, AvatarSlot.top2]),
  extra('Extra', [AvatarSlot.acc]);

  final String label;
  final List<AvatarSlot> slots;
  const AvatarCategory(this.label, this.slots);
}

const Map<AvatarCategory, List<AvatarPart>> kParts = {
  AvatarCategory.hair: [
    AvatarPart('none', 'Bald'),
    AvatarPart('short', 'Short'),
    AvatarPart('spiky', 'Spiky'),
    AvatarPart('long', 'Long'),
    AvatarPart('bun', 'Bun'),
    AvatarPart('ponytail', 'Ponytail'),
    AvatarPart('curly', 'Curly'),
    AvatarPart('braids', 'Braids'),
    AvatarPart('mohawk', 'Mohawk', AvatarUnlock(battles: 5)),
  ],
  AvatarCategory.eyes: [
    AvatarPart('round', 'Round'),
    AvatarPart('big', 'Big'),
    AvatarPart('narrow', 'Sharp'),
    AvatarPart('sleepy', 'Sleepy'),
    AvatarPart('happy', 'Happy'),
  ],
  AvatarCategory.mouth: [
    AvatarPart('smile', 'Smile'),
    AvatarPart('grin', 'Grin'),
    AvatarPart('neutral', 'Calm'),
    AvatarPart('open', 'Open'),
    AvatarPart('smirk', 'Smirk'),
  ],
  AvatarCategory.beard: [
    AvatarPart('none', 'None'),
    AvatarPart('moustache', 'Moustache'),
    AvatarPart('goatee', 'Goatee'),
    AvatarPart('mutton', 'Mutton'),
    AvatarPart('beard', 'Beard'),
    AvatarPart('longbeard', 'Long beard', AvatarUnlock(battles: 3)),
  ],
  AvatarCategory.skin: [],
  AvatarCategory.top: [
    AvatarPart('tunic', 'Tunic'),
    AvatarPart('tank', 'Tank top'),
    AvatarPart('vest', 'Vest'),
    AvatarPart('apron', 'Apron'),
    AvatarPart('hoodie', 'Hoodie'),
    AvatarPart('jacket', 'Jacket', AvatarUnlock(stars: 20)),
    AvatarPart('robe', 'Robe', AvatarUnlock(battles: 5)),
    AvatarPart('armor', 'Armor', AvatarUnlock(battles: 10)),
  ],
  AvatarCategory.bottom: [
    AvatarPart('trousers', 'Trousers'),
    AvatarPart('shorts', 'Shorts'),
    AvatarPart('skirt', 'Skirt'),
    AvatarPart('greaves', 'Greaves', AvatarUnlock(battles: 10)),
  ],
  AvatarCategory.shoes: [
    AvatarPart('shoes', 'Shoes'),
    AvatarPart('boots', 'Boots'),
    AvatarPart('sandals', 'Sandals'),
  ],
  AvatarCategory.hat: [
    AvatarPart('none', 'None'),
    AvatarPart('cap', 'Cap'),
    AvatarPart('headband', 'Headband'),
    AvatarPart('hood', 'Hood'),
    AvatarPart('wide', 'Wide hat'),
    AvatarPart('helmet', 'Helmet', AvatarUnlock(battles: 15)),
    AvatarPart('wizard', 'Wizard hat', AvatarUnlock(floor: 10)),
    AvatarPart('crown', 'Crown', AvatarUnlock(stars: 60)),
  ],
  AvatarCategory.extra: [
    AvatarPart('none', 'None'),
    AvatarPart('glasses', 'Glasses'),
    AvatarPart('scarf', 'Scarf'),
    AvatarPart('backpack', 'Backpack'),
    AvatarPart('eyepatch', 'Eye patch', AvatarUnlock(battles: 8)),
    AvatarPart('cape', 'Cape', AvatarUnlock(guild: true)),
  ],
};

AvatarPart? partFor(AvatarCategory c, String id) {
  for (final p in kParts[c] ?? const <AvatarPart>[]) {
    if (p.id == id) return p;
  }
  return null;
}
