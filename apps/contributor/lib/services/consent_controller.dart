import 'package:flutter/widgets.dart';

import '../models/consent.dart';
import '../models/contribution.dart';
import 'consent_store.dart';

/// Holds the first-run consent state for the widget tree.
///
/// It is a [ChangeNotifier] so that answering the consent prompt removes the
/// blocking gate without a navigation round-trip, and so that any screen can
/// ask whether capture is allowed.
class ConsentController extends ChangeNotifier {
  ConsentController({required ConsentStore store, ConsentState? initial})
      : _store = store,
        _state = initial,
        _loaded = initial != null;

  final ConsentStore _store;
  ConsentState? _state;
  bool _loaded;

  /// True once [load] has completed. Before that the app must not assume
  /// anything; the gate treats "not loaded" as "no decision yet", which fails
  /// closed (capture stays blocked).
  bool get isLoaded => _loaded;

  ConsentState? get state => _state;

  bool get hasDecision => _state != null;

  bool get isGranted => _state?.isGranted ?? false;

  /// The contribution-carried consent record, or null when declined/undecided.
  ConsentRecord? get record => _state?.record;

  /// Reads the stored decision. Safe to call more than once.
  Future<void> load() async {
    _state = await _store.read();
    _loaded = true;
    notifyListeners();
  }

  /// Records a decision and persists it. [now] is injectable for tests.
  Future<void> decide(ConsentDecision decision, {DateTime? now}) async {
    final state = ConsentState(
      decision: decision,
      decidedAt: (now ?? DateTime.now()).toUtc(),
    );
    _state = state;
    _loaded = true;
    await _store.write(state);
    notifyListeners();
  }

  /// Forgets the decision so the app asks again.
  Future<void> revoke() async {
    _state = null;
    _loaded = true;
    await _store.clear();
    notifyListeners();
  }
}

/// Makes the [ConsentController] available to descendants.
class ConsentScope extends InheritedNotifier<ConsentController> {
  const ConsentScope({
    super.key,
    required ConsentController controller,
    required super.child,
  }) : super(notifier: controller);

  static ConsentController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ConsentScope>();
    assert(scope != null, 'No ConsentScope found in context');
    return scope!.notifier!;
  }

  /// The controller, or null when there is no scope (e.g. a screen mounted
  /// standalone in a test). Callers treat null as "no gate to enforce".
  static ConsentController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConsentScope>()?.notifier;
}
