import '../services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Sandboxed in-app browser used by the modals.
///
/// Links (jkbmsr.com, Polar checkout) open inside our own chrome — header,
/// progress bar, footer — instead of bouncing the user to the system browser
/// where they lose all app context. Navigation is restricted to the host (and
/// subdomains) of the initially opened URL, so a link inside the checkout
/// page can never silently steer the user somewhere else. Escaping to the
/// real browser stays available as an explicit footer action.
class InAppBrowserModal extends StatefulWidget {
  final String initialUrl;
  final String title;

  /// Optional interception hook: called for every navigation request. Return
  /// a non-null result string to pop the browser immediately with that value
  /// (the navigation itself is prevented); return null to load normally.
  /// Used by the donation flow to catch the embed page's success/closed
  /// hand-off URLs and turn them into a typed dialog result.
  final String? Function(String requestUrl)? onIntercept;

  const InAppBrowserModal({
    super.key,
    required this.initialUrl,
    required this.title,
    this.onIntercept,
  });

  static Route<T> route<T>({required String initialUrl, required String title}) {
    return MaterialPageRoute<T>(
      builder: (_) => InAppBrowserModal(initialUrl: initialUrl, title: title),
      fullscreenDialog: true,
    );
  }

  @override
  State<InAppBrowserModal> createState() => _InAppBrowserModalState();
}

class _InAppBrowserModalState extends State<InAppBrowserModal> {
  late final WebViewController _controller;
  late final Uri _initialUri;
  bool _canGoBack = false;
  bool _loadedOnce = false;
  String? _error;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _initialUri = Uri.parse(widget.initialUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF131A20))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) async {
          setState(() => _progress = progress / 100.0);
          final canGoBack = await _controller.canGoBack();
          if (mounted && canGoBack != _canGoBack) {
            setState(() => _canGoBack = canGoBack);
          }
        },
        onPageFinished: (_) {
          _loadedOnce = true;
          if (mounted) setState(() => _progress = 0);
        },
        onNavigationRequest: _gateNavigation,
        onWebResourceError: (error) {
          // Only surface failures for the initial page load; a blocked asset
          // inside the checkout flow shouldn't alarm the user.
          if (!_loadedOnce && mounted) {
            setState(() => _error = error.description);
          }
        },
      ))
      ..loadRequest(_initialUri);
  }

  /// Allow only https on the initial host (or its subdomains). about:blank is
  /// permitted since checkout flows use it as an intermediate frame target.
  NavigationDecision _gateNavigation(NavigationRequest request) {
    // Same-origin result hand-off (donation success/closed, etc.) — pop with
    // the typed result instead of navigating.
    final intercept = widget.onIntercept;
    if (intercept != null) {
      final result = intercept(request.url);
      if (result != null) {
        Navigator.of(context).pop(result);
        return NavigationDecision.prevent;
      }
    }
    final uri = Uri.tryParse(request.url);
    final initialHost = _initialUri.host.toLowerCase();
    final host = uri?.host.toLowerCase();
    final allowed = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'about') &&
        host != null &&
        (host == initialHost || host.endsWith('.$initialHost'));
    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  Future<void> _openInSystemBrowser() async {
    final current = await _controller.currentUrl();
    final uri = Uri.parse(current ?? widget.initialUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser available; nothing sane to do inside a fullscreen page.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D10),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF131A20),
                border: Border(bottom: BorderSide(color: Color(0xFF1E2830))),
              ),
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _canGoBack ? 'Back' : 'Close',
                    icon: Icon(
                      _canGoBack ? Icons.arrow_back_rounded : Icons.close_rounded,
                      color: const Color(0xFF94A3B8),
                      size: 20,
                    ),
                    onPressed: () async {
                      if (_canGoBack) {
                        await _controller.goBack();
                      } else if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF1F5F9),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.lock_rounded,
                                size: 10, color: Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _initialUri.host,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.0, color: Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_canGoBack)
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF64748B), size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
            // ── Progress hairline ───────────────────────────────────────
            SizedBox(
              height: 2,
              child: _progress > 0
                  ? LinearProgressIndicator(
                      value: _progress,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                    )
                  : const SizedBox.shrink(),
            ),
            // ── Page ────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_error != null && !_loadedOnce)
                    Container(
                      color: AppColors.bgNested(context),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded,
                              color: Color(0xFF64748B), size: 40),
                          const SizedBox(height: 12),
                          const Text(
                            "Couldn't load this page.",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF1F5F9),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Check your internet connection and try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: BorderSide(color: AppColors.borderColor(context)),
                            ),
                            onPressed: () {
                              setState(() => _error = null);
                              _controller.reload();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('RETRY',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // ── Footer ──────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF131A20),
                border: Border(top: BorderSide(color: Color(0xFF1E2830))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Reload',
                    icon: const Icon(Icons.refresh_rounded,
                        color: Color(0xFF94A3B8), size: 20),
                    onPressed: () => _controller.reload(),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                    ),
                    onPressed: _openInSystemBrowser,
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text(
                      'SYSTEM BROWSER',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
