import 'package:flutter/material.dart';

import '../theme/cream_kit.dart';

/// A scrolling area that SAYS when there is more (user 2026-09-22, the fight
/// card's rewards: "Reward muss ausklappbar sein oder irgendwie signalisieren,
/// falls es mehr Rewards hat, als angezeigt wird"; the same for the Storehouse's
/// effects): while the end has not been reached, the last visible line fades
/// out and a small gold "more" tab sits on it. Tapping the tab scrolls on; at
/// the end both disappear.
///
/// [builder] gets the controller to hand to its scrollable. [fade] should be the
/// colour of the surface the list sits on.
class ScrollCue extends StatefulWidget {
  final Axis axis;
  final Color fade;
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  const ScrollCue({
    super.key,
    this.axis = Axis.vertical,
    this.fade = CreamPalette.paperBottom,
    required this.builder,
  });

  @override
  State<ScrollCue> createState() => _ScrollCueState();
}

class _ScrollCueState extends State<ScrollCue> {
  final _scroll = ScrollController();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
    // The extent is known only after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(ScrollCue old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final more = _scroll.position.maxScrollExtent - _scroll.offset > 2;
    if (more != _more) setState(() => _more = more);
  }

  void _next() {
    if (!_scroll.hasClients) return;
    final step = widget.axis == Axis.vertical ? 70.0 : 160.0;
    _scroll.animateTo(
      (_scroll.offset + step).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return false;
          },
          child: widget.builder(context, _scroll),
        ),
        if (_more) ...[
          Positioned(
            left: vertical ? 0 : null,
            right: 0,
            top: vertical ? null : 0,
            bottom: 0,
            width: vertical ? null : 34,
            height: vertical ? 30 : null,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: vertical
                        ? Alignment.topCenter
                        : Alignment.centerLeft,
                    end: vertical
                        ? Alignment.bottomCenter
                        : Alignment.centerRight,
                    colors: [widget.fade.withValues(alpha: 0), widget.fade],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: vertical ? 0 : null,
            right: 0,
            top: vertical ? null : 0,
            bottom: vertical ? 0 : 0,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _next,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: vertical ? 10 : 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: CreamPalette.gold,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: CreamPalette.goldDeep,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    vertical ? '▾ more' : '▸',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: CreamPalette.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
