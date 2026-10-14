import 'contribution.dart';

/// The user's first-run consent decision.
///
/// Plan §3.1: the app is opt-in with the default **off**. The decision is
/// stored locally and never transmitted by itself; a granted decision is only
/// reflected inside a contribution as its `consent` record (provenance), never
/// as an identity.
enum ConsentDecision {
  /// The user turned the opt-in on and agreed to contribute.
  granted,

  /// The user chose "Not now". The app stays fully usable locally; capture
  /// remains blocked until consent is granted.
  declined,
}

/// The persisted consent state: the decision and when it was made.
class ConsentState {
  /// Scope string written to a contribution's `consent.scope`.
  ///
  /// Bumped only if what the user is agreeing to changes materially, so a
  /// stored decision can be told apart from a later, broader one.
  static const String scope = 'telemetry+frames';

  final ConsentDecision decision;
  final DateTime decidedAt;

  const ConsentState({required this.decision, required this.decidedAt});

  bool get isGranted => decision == ConsentDecision.granted;

  Map<String, dynamic> toJson() => {
        'decision': decision.name,
        'decidedAt': Contribution.utcIso(decidedAt),
        'scope': scope,
      };

  /// Returns null when the document is unusable, so a corrupt value is treated
  /// as "not yet answered" (which blocks capture) rather than as consent.
  static ConsentState? tryFromJson(Map<String, dynamic> json) {
    final raw = json['decision'];
    final at = json['decidedAt'];
    if (raw is! String || at is! String) return null;
    ConsentDecision? decision;
    for (final d in ConsentDecision.values) {
      if (d.name == raw) {
        decision = d;
        break;
      }
    }
    if (decision == null) return null;
    final decidedAt = DateTime.tryParse(at);
    if (decidedAt == null) return null;
    return ConsentState(decision: decision, decidedAt: decidedAt.toUtc());
  }

  /// The contribution-carried record of this decision, or null when declined.
  ConsentRecord? get record => isGranted
      ? ConsentRecord(givenAt: decidedAt.toUtc(), scope: scope)
      : null;
}
