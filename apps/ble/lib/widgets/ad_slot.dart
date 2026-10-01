import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_sdk.dart';
import '../services/ads_config.dart';
import '../services/entitlement_service.dart';

/// The ad placements that are allowed to exist. One kind today, on purpose:
/// a single, reviewable list beats a format that grows per surface.
enum AdSlotKind {
  /// Standard banner, for the bottom of a read-only status/history screen.
  banner,
}

/// Builds the ad widget for a permitted slot.
///
/// The shipping default ([_buildRealBanner]) is the only code path that talks
/// to the Google Mobile Ads SDK. It is injectable so a widget test can prove
/// the gate order — including that the SDK is never initialised — without a
/// platform channel or a network request.
typedef AdSlotAdBuilder = Widget Function(
  BuildContext context,
  AdsConfig config,
  EntitlementState entitlement,
);

/// The one and only place an ad is allowed to appear in this app.
///
/// Renders nothing at all unless [AdsConfig.mayShowAds] says so, which under
/// the no-defines default is never: no AdMob app id, so
/// `AdsConfig.current.isConfigured` is false. In that state neither an SDK
/// initialisation nor an ad request happens, because [_buildRealBanner] — the
/// only code that could do either — is never reached. The release scripts pass
/// the real ids (see `scripts/ads-defines.sh`), which is what makes this
/// configured in a shipped build.
///
/// When a build IS configured, the decision is still made before anything
/// touches the SDK: a Supporter short-circuits at [mayShowAds] here, and
/// [AdSdk.ensureInitialised] re-checks the same gate before it initialises
/// anything.
///
/// Deliberate exclusions — do not add an [AdSlot] to any of these, whatever
/// the room left on screen:
///  * the Connect/Scanning flow (`devices_screen.dart`, `welcome_screen.dart`);
///  * the Control screen (`control_screen.dart`);
///  * the PIN dialog (`auth_pin_dialog.dart`);
///  * anything rendered while a BLE connection is being established,
///    connecting or disconnecting.
///
/// Ads belong on read-only status/history surfaces, where a user is already
/// looking at stored telemetry and no command can be mis-tapped.
class AdSlot extends StatelessWidget {
  const AdSlot({
    super.key,
    this.slot = AdSlotKind.banner,
    this.config = AdsConfig.current,
    this.adBuilder,
  });

  final AdSlotKind slot;

  /// Defaults to [AdsConfig.current] — the app-wide ad configuration. Tests
  /// pass a configured instance to exercise the enabled path without defines.
  final AdsConfig config;

  /// Overrides the ad widget, for tests only. Left null in the app, so the
  /// real SDK banner is the only thing that can ever render.
  final AdSlotAdBuilder? adBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EntitlementState>(
      valueListenable: EntitlementService.instance.changes,
      builder: (context, entitlement, _) {
        if (!config.mayShowAds(entitlement)) {
          // Nothing in the tree, no reserved height, no spacing: a disabled ad
          // slot must be invisible to layout, semantics and screen readers.
          // This is also the branch that keeps the SDK untouched: no ad widget
          // is built, so nothing can initialise or request one.
          return const SizedBox.shrink();
        }
        return _buildAd(context, config, entitlement);
      },
    );
  }

  /// Only reachable once ads are deliberately configured AND the user is not a
  /// Supporter. Dispatches on [AdSlotKind] so a new format is a new case, not
  /// a new widget scattered across a screen.
  Widget _buildAd(
    BuildContext context,
    AdsConfig config,
    EntitlementState entitlement,
  ) {
    switch (slot) {
      case AdSlotKind.banner:
        return (adBuilder ?? _buildRealBanner)(context, config, entitlement);
    }
  }
}

/// The shipping banner: an anchored adaptive [BannerAd] rendered by [AdWidget].
///
/// This is the only function in the app that initialises the SDK or requests an
/// ad, and it is only ever called after [AdsConfig.mayShowAds] returned true.
Widget _buildRealBanner(
  BuildContext context,
  AdsConfig config,
  EntitlementState entitlement,
) =>
    _AdMobBanner(config: config, entitlement: entitlement);

/// Renders a real AdMob banner, or collapses to nothing while loading, when no
/// ad fills, or when the SDK fails. It must never break the screen it sits on.
class _AdMobBanner extends StatefulWidget {
  const _AdMobBanner({required this.config, required this.entitlement});

  final AdsConfig config;
  final EntitlementState entitlement;

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  BannerAd? _bannerAd;
  BannerAd? _loadedAd;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Re-check the single ad decision at the point of use. This is the gate
      // that must hold for a Supporter: ensureInitialised below returns before
      // touching the SDK when mayShowAds is false.
      if (!widget.config.mayShowAds(widget.entitlement)) return;

      await AdSdk.instance.ensureInitialised(
        widget.config,
        widget.entitlement,
      );
      if (!mounted) return;

      final width = MediaQuery.sizeOf(context).width.truncate();
      AdSize size = AdSize.banner;
      try {
        size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width) ??
            AdSize.banner;
      } catch (_) {
        // No platform sizing available: the fixed 320x50 banner still works.
        size = AdSize.banner;
      }
      if (!mounted) return;

      final ad = BannerAd(
        size: size,
        adUnitId: widget.config.bannerAdUnitId,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() => _loadedAd = ad as BannerAd);
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            _bannerAd = null;
            if (mounted) setState(() {});
          },
        ),
      );
      _bannerAd = ad;
      await ad.load();
    } catch (_) {
      // Offline, no Play services, a malformed id, or no fill: an ad must never
      // surface an error over the telemetry the user is reading.
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _loadedAd;
    if (ad == null) {
      // Loading, no fill, or failed: reserve nothing rather than show a gap.
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
