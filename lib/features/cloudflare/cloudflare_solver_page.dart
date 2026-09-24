import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:soplay/core/system/webview_env.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class CloudflareSolverPage extends StatefulWidget {
  const CloudflareSolverPage({
    super.key,
    required this.baseUrl,
    required this.userAgent,
  });

  final String baseUrl;
  final String userAgent;

  @override
  State<CloudflareSolverPage> createState() => _CloudflareSolverPageState();
}

class _CloudflareSolverPageState extends State<CloudflareSolverPage> {
  final CookieManager _cookieManager = CookieManager.instance();
  Timer? _pollTimer;
  bool _firstLoadDone = false;
  bool _solved = false;
  WebViewEnvironment? _environment;
  bool _environmentReady = false;

  // The address bar: where the page is, and the way to go somewhere else on
  // the site — a login, a mirror domain — which a bare webview gave no way to.
  InAppWebViewController? _web;
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  double _progress = 0;
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    WebViewEnv.ensure().then((env) {
      if (!mounted) return;
      setState(() {
        _environment = env;
        _environmentReady = true;
      });
    });
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _checkCookies(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Future<void> _syncNav(WebUri? url) async {
    final web = _web;
    if (web == null || !mounted) return;
    final back = await web.canGoBack();
    final forward = await web.canGoForward();
    if (!mounted) return;
    setState(() {
      _canBack = back;
      _canForward = forward;
      if (url != null && !_addressFocus.hasFocus) {
        _address.text = url.toString();
      }
    });
  }

  void _go(String typed) {
    var text = typed.trim();
    if (text.isEmpty) return;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return;
    _addressFocus.unfocus();
    _web?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
  }

  Future<void> _openOutside() async {
    final uri = Uri.tryParse(_address.text.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> _hasClearance() async {
    try {
      final cookies = await _cookieManager.getCookies(
        url: WebUri(widget.baseUrl),
      );
      for (final c in cookies) {
        if (c.name == 'cf_clearance' &&
            c.value != null &&
            c.value.toString().isNotEmpty) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _checkCookies() async {
    if (_solved || !mounted) return;
    if (await _hasClearance()) {
      _finishSolved();
    }
  }

  void _finishSolved() {
    if (_solved || !mounted) return;
    _solved = true;
    _pollTimer?.cancel();
    // Only if this page is still the one on top. `_checkCookies` runs on a
    // poll timer, so it can fire in the gap after the user has already left —
    // by pressing Back, or by the manual Done that popped a moment earlier —
    // and a bare `pop` then closes whatever route is now current instead. The
    // symptom is the solver appearing to "work" and taking the page behind it
    // with it.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _onManualDone() async {
    if (await _hasClearance()) {
      _finishSolved();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('cloudflare.hint'.tr()),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _banner(),
            _addressBar(),
            Expanded(
              child: Stack(
                children: [
                  if (_environmentReady)
                    InAppWebView(
                      webViewEnvironment: _environment,
                      initialUrlRequest: URLRequest(
                        url: WebUri(widget.baseUrl),
                      ),
                      initialSettings: InAppWebViewSettings(
                        userAgent: widget.userAgent,
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        thirdPartyCookiesEnabled: true,
                        clearCache: false,
                      ),
                      onWebViewCreated: (controller) => _web = controller,
                      onProgressChanged: (_, progress) {
                        if (mounted) setState(() => _progress = progress / 100);
                      },
                      onUpdateVisitedHistory: (_, url, _) => _syncNav(url),
                      onLoadStart: (_, url) => _syncNav(url),
                      onLoadStop: (controller, url) async {
                        if (mounted && !_firstLoadDone) {
                          setState(() => _firstLoadDone = true);
                        }
                        await _syncNav(url);
                        await _checkCookies();
                      },
                    ),
                  if (!_firstLoadDone)
                    ColoredBox(
                      color: AppColors.background,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
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

  Widget _addressBar() {
    Widget nav(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      color: AppColors.textPrimary,
      disabledColor: AppColors.textHint,
      onPressed: onTap,
    );
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              nav(
                Icons.arrow_back_rounded,
                'webview.back'.tr(),
                _canBack ? () => _web?.goBack() : null,
              ),
              nav(
                Icons.arrow_forward_rounded,
                'webview.forward'.tr(),
                _canForward ? () => _web?.goForward() : null,
              ),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _address,
                    focusNode: _addressFocus,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    onSubmitted: _go,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              nav(
                Icons.refresh_rounded,
                'webview.reload'.tr(),
                () => _web?.reload(),
              ),
              nav(
                Icons.open_in_browser_rounded,
                'webview.open_outside'.tr(),
                _openOutside,
              ),
            ],
          ),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: AppColors.primary,
            ),
        ],
      ),
    );
  }

  Widget _banner() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
            tooltip: 'general.close'.tr(),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'cloudflare.title'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'cloudflare.hint'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kButtonRadius),
              ),
            ),
            onPressed: _onManualDone,
            child: Text('cloudflare.done'.tr()),
          ),
        ],
      ),
    );
  }
}
