import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:soplay/core/system/webview_env.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

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
    super.dispose();
  }

  Future<bool> _hasClearance() async {
    try {
      final cookies =
          await _cookieManager.getCookies(url: WebUri(widget.baseUrl));
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
            Expanded(
              child: Stack(
                children: [
                  if (_environmentReady)
                    InAppWebView(
                      webViewEnvironment: _environment,
                      initialUrlRequest: URLRequest(url: WebUri(widget.baseUrl)),
                      initialSettings: InAppWebViewSettings(
                        userAgent: widget.userAgent,
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        thirdPartyCookiesEnabled: true,
                        clearCache: false,
                      ),
                      onLoadStop: (controller, url) async {
                        if (mounted && !_firstLoadDone) {
                          setState(() => _firstLoadDone = true);
                        }
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

  Widget _banner() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
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
