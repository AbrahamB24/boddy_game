import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Registered as a [MaterialApp] navigator observer so [OrientationLock]
/// can be notified when a screen becomes visible again after the route
/// above it is popped.
final RouteObserver<PageRoute<dynamic>> orientationRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Mix into a screen's [State] to keep it locked to [lockedOrientations]
/// for as long as it's the visible route — including when it's revealed
/// again after a differently-oriented screen pushed on top of it is popped.
mixin OrientationLock<T extends StatefulWidget> on State<T>
    implements RouteAware {
  List<DeviceOrientation> get lockedOrientations;

  void _apply() => SystemChrome.setPreferredOrientations(lockedOrientations);

  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      orientationRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    orientationRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => _apply();

  @override
  void didPopNext() => _apply();

  @override
  void didPop() {}

  @override
  void didPushNext() {}
}
