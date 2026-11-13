import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';
import '../../core/ui/pressable.dart';
import '../guild/guild_service.dart';
import '../social/services/friends_service.dart';
import '../social/widgets/social_kit.dart';
import '../settlement/widgets/voxel_hud.dart' show VoxelHud;
import 'avatar_catalog.dart';
import 'avatar_service.dart';
import 'avatar_spec.dart';
import 'avatar_view.dart';

/// The avatar creator (user 2026-11-13): the figure on the left, the parts and
/// colours of one category on the right. Parts that are not unlocked yet are
/// shown but cannot be taken; tapping one says how to get it.
class AvatarCreatorScreen extends StatefulWidget {
  /// The look to start from (null = what is saved, or the default figure).
  final AvatarSpec? start;

  /// Overrides what the player has reached (tests, a dev tool).
  final AvatarProgress? progress;

  const AvatarCreatorScreen({super.key, this.start, this.progress});

  @override
  State<AvatarCreatorScreen> createState() => _AvatarCreatorScreenState();
}

const Set<AvatarCategory> _wholeFigure = {
  AvatarCategory.top,
  AvatarCategory.bottom,
  AvatarCategory.shoes,
};

class _AvatarCreatorScreenState extends State<AvatarCreatorScreen> {
  late AvatarSpec _spec = widget.start ?? AvatarSpec.defaults;
  late AvatarProgress _progress =
      widget.progress ?? AvatarProgress.current();
  AvatarCategory _cat = AvatarCategory.hair;
  String? _username;
  String _note = '';
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = widget.start == null
        ? await AvatarService.instance.loadMine()
        : null;
    String? name;
    try {
      name = await FriendsService().loadMyUsername();
    } catch (_) {}
    if (widget.progress == null) {
      await GuildMembership.instance.refresh();
    }
    if (!mounted) return;
    setState(() {
      if (saved != null) _spec = saved;
      _username = name;
      if (widget.progress == null) _progress = AvatarProgress.current();
      _loaded = true;
    });
  }

  void _pick(AvatarCategory c, AvatarPart p) {
    if (!p.unlock.isMet(_progress)) {
      setState(() => _note = p.unlock.hint);
      return;
    }
    setState(() {
      _spec = _spec.withPart(c, p.id);
      _note = '';
    });
  }

  void _color(AvatarSlot s, int i) => setState(() {
    _spec = _spec.withColor(s, i);
    _note = '';
  });

  /// A part the player no longer (or never) had is swapped for the first open
  /// one of its category, so a hand-edited look cannot be saved.
  AvatarSpec _legal(AvatarSpec s) {
    var out = s;
    for (final c in AvatarCategory.values) {
      final parts = kParts[c] ?? const <AvatarPart>[];
      final cur = partFor(c, s.partOf(c));
      if (cur != null && !cur.unlock.isMet(_progress) && parts.isNotEmpty) {
        out = out.withPart(c, parts.first.id);
      }
    }
    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _note = '';
    });
    final spec = _legal(_spec);
    final ok = await AvatarService.instance.saveMine(spec, username: _username);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(spec);
    } else {
      setState(() {
        _saving = false;
        _note = 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: 'Avatar',
    maxWidth: 960,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 236, child: _stage()),
        const SizedBox(width: 12),
        Expanded(child: _editor()),
      ],
    ),
  );

  Widget _stage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Container(
          decoration: raisedTile(),
          padding: const EdgeInsets.all(6),
          child: Center(
            child: LayoutBuilder(
              builder: (context, box) => AvatarView(
                spec: _spec,
                size: box.biggest.shortestSide,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: SocialTileButton(
              'Random',
              height: 34,
              onTap: _loaded
                  ? () => setState(
                      () => _spec = AvatarSpec.random(_progress),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Pressable(
              onTap: _loaded && !_saving ? _save : null,
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: goldButton(active: _loaded && !_saving),
                child: Text(
                  _saving ? 'Saving…' : 'Save',
                  style: const TextStyle(
                    color: CreamPalette.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final c in AvatarCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Pressable(
                  onTap: () => setState(() {
                    _cat = c;
                    _note = '';
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: c == _cat ? goldButton() : menuButton(),
                    child: Text(
                      c.label,
                      style: TextStyle(
                        color: c == _cat ? CreamPalette.ink : VoxelHud.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(child: _parts()),
      if (_cat.slots.isNotEmpty) ...[
        const SizedBox(height: 6),
        _colors(),
      ],
      SizedBox(
        height: 18,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _note,
            maxLines: 1,
            style: FoE.dim(size: 11).copyWith(color: CreamPalette.warn),
          ),
        ),
      ),
    ],
  );

  Widget _parts() {
    final parts = kParts[_cat] ?? const <AvatarPart>[];
    if (parts.isEmpty) {
      return Center(
        child: Text(
          'Pick a skin tone below.',
          style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 84,
        mainAxisExtent: 92,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: parts.length,
      itemBuilder: (context, i) {
        final p = parts[i];
        final on = _spec.partOf(_cat) == p.id;
        final open = p.unlock.isMet(_progress);
        return Pressable(
          onTap: () => _pick(_cat, p),
          child: Container(
            decoration: raisedTile(lit: on, locked: !open),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: open ? 1 : 0.35,
                        child: AvatarView(
                          spec: _spec.withPart(_cat, p.id),
                          size: 62,
                          // Clothes and shoes are judged on the whole figure.
                          bust: !_wholeFigure.contains(_cat),
                        ),
                      ),
                      if (!open)
                        const PixelIcon(
                          Icons.lock,
                          size: 20,
                          color: VoxelHud.ink,
                        ),
                    ],
                  ),
                ),
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: VoxelHud.ink,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _colors() {
    final multi = _cat.slots.length > 1;
    String label(AvatarSlot s) => switch (s) {
      AvatarSlot.top2 => 'Trim',
      AvatarSlot.top => 'Colour',
      AvatarSlot.hat => 'Colour',
      _ => 'Colour',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in _cat.slots)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    multi ? label(s) : 'Colour',
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (var i = 0; i < paletteFor(s).length; i++)
                        Pressable(
                          onTap: () => _color(s, i),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: paletteFor(s)[i],
                              border: Border.all(
                                color: _spec.colorIndex(s) == i
                                    ? CreamPalette.gold
                                    : CreamPalette.tan.withValues(alpha: 0.6),
                                width: _spec.colorIndex(s) == i ? 2.5 : 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
