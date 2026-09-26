import '../models/bms_models.dart';
import 'brand_registry.dart';

/// One plausible brand for a device, ranked by confidence.
class DetectionCandidate {
  final BmsBrand brand;

  /// 0..1 confidence. 1.0 = an unambiguous name match; 0.6 = exclusive
  /// GATT service (only one brand uses it); 0.4 = a service shared by
  /// several brands (0xFF00 family, 0xFFE0 family).
  final double confidence;

  /// True when this candidate can only be confirmed by sending its probe
  /// request and waiting for a real telemetry frame — an active candidate
  /// list that the connection flow steps through.
  final bool requiresProbe;

  /// Human-readable summary of why this brand was suggested, shown in the
  /// device picker.
  final String reason;

  const DetectionCandidate({
    required this.brand,
    required this.confidence,
    required this.requiresProbe,
    required this.reason,
  });
}

/// Scores how strongly the scanned [name] + discovered GATT [serviceUuids]
/// point at each supported brand. All weights match the plan: a name match
/// is authoritative (1.0), a service that only one supported brand exposes
/// is strong (0.6), and a shared service (JK02/JBD/Seplos/Tianpower/KS all
/// sit on 0xFF00; JK/ANT/Topband share 0xFFE0) is a weak hint (0.4).
class DetectionEngine {
  static const double _nameConfidence = 1.0;
  static const double _exclusiveServiceConfidence = 0.6;
  static const double _sharedServiceConfidence = 0.4;

  /// Ranks every candidate brand for a device down to zero confidence.
  /// Scans only the *advertised* services first when [advertisedUuids] is
  /// provided; otherwise [serviceUuids] (post-discovery) is used.
  static List<DetectionCandidate> candidatesFor({
    required String name,
    required Set<String> serviceUuids,
  }) {
    final lowerName = name.toLowerCase().trim();
    final lowerUuids = serviceUuids.map((u) => u.toLowerCase()).toSet();
    final candidates = <DetectionCandidate>[];

    for (final brand in BrandRegistry.supportedBrands) {
      final signature = BrandRegistry.signatureFor(brand.brand);
      if (signature == null) continue;

      double best = 0.0;
      final reasons = <String>[];

      if (signature.matchesName(lowerName)) {
        best = _nameConfidence;
        reasons.add('device name matches');
      }

      for (final serviceUuid in signature.serviceUuids) {
        if (!lowerUuids.contains(serviceUuid)) continue;
        final sharing = BrandRegistry.serviceSharingCount(serviceUuid);
        final confidence = sharing <= 1 ? _exclusiveServiceConfidence : _sharedServiceConfidence;
        if (confidence > best) {
          best = confidence;
          reasons.add(sharing <= 1
              ? 'exclusive service match'
              : 'service shared by $sharing brands');
        }
      }

      if (best <= 0.0) continue;
      candidates.add(DetectionCandidate(
        brand: brand.brand,
        confidence: best,
        requiresProbe: best < 1.0 && signature.probeRequest != null,
        reason: reasons.join(', '),
      ));
    }

    candidates.sort((a, b) {
      final c = b.confidence.compareTo(a.confidence);
      if (c != 0) return c;
      // Tie-break: prefer name matches over service matches.
      final nameA = a.confidence == _nameConfidence ? 1 : 0;
      final nameB = b.confidence == _nameConfidence ? 1 : 0;
      return nameB.compareTo(nameA);
    });
    return candidates;
  }

  /// The single best candidate, or null when nothing could be inferred.
  static DetectionCandidate? bestFor({required String name, required Set<String> serviceUuids}) {
    final candidates = candidatesFor(name: name, serviceUuids: serviceUuids);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Whether [candidate] can be confirmed without sending anything to the
  /// hardware (name match only) — those are safe to accept immediately.
  static bool isCertain(DetectionCandidate candidate) => candidate.confidence >= _nameConfidence;
}