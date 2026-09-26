import 'package:flutter/widgets.dart';

/// Split out of router.dart so services that need to push a toast/navigate
/// on their own (e.g. SessionExpiryHandler, called from deep inside
/// APIClient) can import just this key without pulling in router.dart's
/// full route table, which would create an import cycle back through the
/// screens it routes to.
final GlobalKey<NavigatorState> jkbmsrNavigatorKey = GlobalKey<NavigatorState>();
