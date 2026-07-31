import 'package:flutter/material.dart';

import '../theme/foe_theme.dart';
import 'feel.dart';

/// The sound/haptics switch, next to the bell (user 2026-07-30).
///
/// A game that makes noise has to be silenceable in ONE tap from the screen you
/// are on — a mute buried in a settings page is a mute nobody finds on the bus.
/// So the icon itself is the switch: tap it and the sound stops.
///
/// Haptics get their own line in the long-press sheet rather than a second icon
/// in the header. Silent-but-buzzing is a real preference (and the usual one in
/// public), but it is not the one people reach for in a hurry.
class FeelButton extends StatefulWidget {
  const FeelButton({super.key});

  @override
  State<FeelButton> createState() => _FeelButtonState();
}

class _FeelButtonState extends State<FeelButton> {
  Future<void> _toggleSound() async {
    await Feel.setSoundOn(!Feel.soundOn);
    // Confirm with the thing itself: switching sound ON should make a sound.
    if (Feel.soundOn) Feel.tap();
    if (mounted) setState(() {});
  }

  Future<void> _openMore() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FoE.panelDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            16 + MediaQuery.of(ctx).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Feel', style: FoE.title(size: 14)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: FoE.gold,
                value: Feel.soundOn,
                onChanged: (v) async {
                  await Feel.setSoundOn(v);
                  if (v) Feel.tap();
                  setSheet(() {});
                  if (mounted) setState(() {});
                },
                title: Text('Sound effects', style: FoE.label(size: 13)),
                subtitle: Text(
                  'Short cues when something lands.',
                  style: FoE.dim(size: 11),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: FoE.gold,
                value: Feel.hapticsOn,
                onChanged: (v) async {
                  await Feel.setHapticsOn(v);
                  setSheet(() {});
                  if (mounted) setState(() {});
                },
                title: Text('Vibration', style: FoE.label(size: 13)),
                subtitle: Text(
                  'A nudge for placing, hiring, hatching and refusals.',
                  style: FoE.dim(size: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _toggleSound,
      onLongPress: _openMore,
      borderRadius: BorderRadius.circular(FoE.radiusSmall),
      child: SizedBox(
        width: FoE.tapTarget,
        height: FoE.tapTarget,
        child: Icon(
          Feel.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          size: 20,
          color: Feel.soundOn ? FoE.gold : FoE.textDim,
        ),
      ),
    ),
  );
}
