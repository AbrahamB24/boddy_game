import 'package:flutter/material.dart';

/// The app's one navigator key. Things that live ABOVE the navigator — the PvP
/// banner that can appear on any screen — have no context that can push a
/// route; they use this.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
