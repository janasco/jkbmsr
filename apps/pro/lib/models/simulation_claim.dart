/// What the server answered about today's simulated session.
///
/// `credited` is 0 when the day was already claimed, and `reason` says so. The
/// balance is the account's, not a gateway's.
class SimulationClaimResult {
  const SimulationClaimResult({
    required this.credited,
    required this.reason,
    required this.balance,
  });

  final int credited;
  final String? reason;
  final int balance;

  factory SimulationClaimResult.fromJson(Map<String, dynamic> json) {
    return SimulationClaimResult(
      credited: (json['credited'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String?,
      balance: (json['balance'] as num?)?.toInt() ?? 0,
    );
  }
}
