import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/game_text.dart';
import '../../core/ui/pressable.dart';
import '../creatures/models/species_def.dart';
import '../creatures/services/creatures_controller.dart';
import '../social/services/friends_service.dart';
import '../social/widgets/social_kit.dart';
import '../settlement/widgets/voxel_hud.dart' show VoxelHud;
import 'avatar_service.dart';
import 'player_portrait.dart';

/// Choose the picture other players see next to your name: any stage of any
/// monster line you have seen in your bestiary (user 2026-11-13). A stage counts
/// as seen once your best monster of that line has reached it — the same rule the
/// bestiary uses to un-silhouette a tile.
class PortraitPickerScreen extends StatefulWidget {
  /// The portrait to start from (null = what is saved).
  final PortraitRef? start;

  const PortraitPickerScreen({super.key, this.start});

  @override
  State<PortraitPickerScreen> createState() => _PortraitPickerScreenState();
}

class _PortraitPickerScreenState extends State<PortraitPickerScreen> {
  final _ctrl = CreaturesController();
  PortraitRef? _picked;
  String? _username;
  bool _loaded = false;
  bool _saving = false;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _picked = widget.start;
    _load();
  }

  Future<void> _load() async {
    await _ctrl.load();
    final saved = widget.start == null
        ? await AvatarService.instance.loadMine()
        : null;
    String? name;
    try {
      name = await FriendsService().loadMyUsername();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _picked ??= saved;
      _username = name;
      _loaded = true;
    });
  }

  /// Every stage the player has seen, species by rarity then name (the order of
  /// the bestiary).
  List<PortraitRef> _seen() {
    final best = <String, int>{};
    for (final c in _ctrl.creatures) {
      if (c.stage > (best[c.speciesId] ?? -1)) best[c.speciesId] = c.stage;
    }
    final species = kSpeciesDefs.values.where((s) => best.containsKey(s.id)).toList()
      ..sort((a, b) {
        final r = a.rarity.index.compareTo(b.rarity.index);
        return r != 0 ? r : a.name.compareTo(b.name);
      });
    return [
      for (final s in species)
        for (var st = 0; st <= (best[s.id] ?? -1).clamp(0, 2); st++)
          PortraitRef(s.id, st),
    ];
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _note = '';
    });
    final ok = await AvatarService.instance.saveMine(
      _picked,
      username: _username,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(_picked);
    } else {
      setState(() {
        _saving = false;
        _note = 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: 'Portrait',
    child: ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final seen = _seen();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 200, child: _stage()),
            const SizedBox(width: 12),
            Expanded(child: _grid(seen)),
          ],
        );
      },
    ),
  );

  Widget _stage() {
    final ref = _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: raisedTile(),
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, box) => ref == null
                          ? SocialAvatar.letter(
                              _username ?? '?',
                              size: box.biggest.shortestSide * 0.7,
                            )
                          : PortraitView(
                              ref: ref,
                              size: box.biggest.shortestSide,
                            ),
                    ),
                  ),
                ),
                Text(
                  ref?.name ?? 'No portrait',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 13).copyWith(color: kBoxInk),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SocialTileButton(
                'Clear',
                height: 34,
                onTap: _loaded && _picked != null
                    ? () => setState(() => _picked = null)
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
  }

  Widget _grid(List<PortraitRef> seen) {
    if (seen.isEmpty) {
      return Center(
        child: Text(
          _loaded
              ? 'Catch a monster and it shows up here.'
              : '…',
          style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 92,
        mainAxisExtent: 104,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: seen.length,
      itemBuilder: (context, i) {
        final r = seen[i];
        final on = _picked == r;
        return Pressable(
          onTap: () => setState(() {
            _picked = r;
            _note = '';
          }),
          child: Container(
            decoration: raisedTile(lit: on),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => PortraitView(
                      ref: r,
                      size: box.biggest.shortestSide,
                    ),
                  ),
                ),
                Text(
                  r.name,
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
}
