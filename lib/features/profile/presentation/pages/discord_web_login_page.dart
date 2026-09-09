import 'dart:collection';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/theme/app_colors.dart';

/// Signs in to Discord inside the app and hands the user token back to whoever
/// pushed this route, via `context.pop(token)`. Pops with nothing if the viewer
/// leaves without signing in.
///
/// ## Why a WebView at all
///
/// On a phone there is no Discord client to speak IPC to, so Rich Presence has
/// to identify to the gateway with the account's own token. Until now the only
/// way to supply one was to dig it out of a browser's devtools and paste it —
/// which almost nobody can do, and which is the step people gave up at. Here
/// they sign in on Discord's own login page and the token is picked up from the
/// requests that page makes afterwards. The paste path stays behind the app-bar
/// action for anyone who already has a token or would rather not sign in here.
///
/// ## How the token is captured
///
/// Once signed in, Discord's web client puts the token in an `Authorization`
/// header on every call to its API. `XMLHttpRequest.setRequestHeader` and
/// `fetch` are patched — as a user script at document start, so it runs before
/// any of Discord's code, and again on every load in case a navigation replaced
/// the window — to forward that header to Dart. That is the primary path, and
/// it survives Discord renaming its internals. A second, opportunistic path
/// reads the token out of the webpack module store once the app has loaded; it
/// is the one that breaks first whenever Discord ships, so it only ever assists.
///
/// ## What is deliberately not done
///
/// The session is incognito and nothing it writes is kept: the credential Sozo
/// holds is the token, in the platform keystore, never a signed-in cookie jar.
/// No script reads or touches the form — the viewer types their password into
/// Discord's page, not into Sozo — and the scripts here only ever see a request
/// header that Discord's own code chose to send.
class DiscordWebLoginPage extends StatefulWidget {
  const DiscordWebLoginPage({super.key});

  @override
  State<DiscordWebLoginPage> createState() => _DiscordWebLoginPageState();
}

class _DiscordWebLoginPageState extends State<DiscordWebLoginPage> {
  static const String _loginUrl = 'https://discord.com/login';

  /// Discord serves the full web client only to what it takes for a desktop
  /// browser. With a mobile UA the login page is replaced by a "get the app"
  /// wall that has no form on it, so there would be nothing to sign in to.
  static const String _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String _handler = 'sozoDiscordToken';

  InAppWebViewController? _controller;
  bool _firstLoadDone = false;
  bool _done = false;

  /// Forwards any `Authorization` header the page sets to Dart. Idempotent via
  /// `window.__sozoDiscord`, and sends at most once via `window.__sozoSent`, so
  /// re-injecting on every load is safe and a chatty page cannot spam Dart.
  static const String _interceptor = r'''
(function(){
  if (window.__sozoDiscord) return; window.__sozoDiscord = true;
  function send(v){
    try{
      if (!v) return;
      v = String(v);
      if (window.__sozoSent || v.length < 40 || v.indexOf('Bearer') === 0) return;
      var b = window.flutter_inappwebview;
      if (b && typeof b.callHandler === 'function'){
        window.__sozoSent = true;
        b.callHandler('sozoDiscordToken', v);
      }
    }catch(_){}
  }
  try{
    var s = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function(k, v){
      try{ if (k && String(k).toLowerCase() === 'authorization') send(v); }catch(_){}
      return s.apply(this, arguments);
    };
  }catch(_){}
  try{
    var f = window.fetch;
    window.fetch = function(){
      try{
        var o = arguments[1];
        if (o && o.headers){
          var h = o.headers;
          var a = (h.get && h.get('authorization')) || h.authorization || h.Authorization;
          send(a);
        }
      }catch(_){}
      return f.apply(this, arguments);
    };
  }catch(_){}
})();
''';

  /// Pulls the token out of Discord's webpack module store. Synchronous; returns
  /// the token or null. Tries the export shapes Discord has used so far, since
  /// they rename them between releases — which is why this is the fallback.
  static const String _grabber = r'''
(function(){
  var token = null;
  function pick(ex){
    if (!ex) return null;
    try{
      if (ex.default && typeof ex.default.getToken === 'function') return ex.default.getToken();
      if (typeof ex.getToken === 'function') return ex.getToken();
      if (ex.Z && typeof ex.Z.getToken === 'function') return ex.Z.getToken();
      if (ex.ZP && typeof ex.ZP.getToken === 'function') return ex.ZP.getToken();
    }catch(_){}
    return null;
  }
  try{
    var chunk = (window.webpackChunkdiscord_app = window.webpackChunkdiscord_app || []);
    chunk.push([[Symbol('sozo')], {}, function(req){
      try{
        for (var id in req.c){
          var t = pick(req.c[id] && req.c[id].exports);
          if (t){ token = t; return; }
        }
      }catch(_){}
    }]);
  }catch(_){}
  return token;
})()
''';

  /// Accepts a candidate from any of the three sources exactly once.
  void _accept(String raw) {
    if (_done) return;
    final token = _clean(raw);
    if (token == null) return;
    _done = true;
    if (mounted) context.pop(token);
  }

  /// A token, or null. `evaluateJavascript` hands strings back JSON-quoted, so
  /// the quotes and escapes come off first; then the same floor the page-side
  /// `send` applies, so a paste is held to the same bar as a capture.
  static String? _clean(String raw) {
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    s = s.replaceAll(r'\"', '"').replaceAll(r'\/', '/').trim();
    if (s.isEmpty || s == 'null' || s == 'undefined') return null;
    if (s.startsWith('Bearer')) return null;
    if (s.length < 40 || s.contains(' ')) return null;
    return s;
  }

  Future<void> _tryGrab() async {
    final c = _controller;
    if (_done || c == null) return;
    try {
      final r = await c.evaluateJavascript(source: _grabber);
      if (r != null) _accept(r.toString());
    } catch (_) {
      // Not the app page yet, or Discord moved the store. The header
      // interceptor is the path that matters; this one only shortens the wait.
    }
  }

  Future<void> _paste() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('discord.web_login_paste_title'.tr()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'discord.web_login_paste_hint'.tr(),
            hintStyle: const TextStyle(color: AppColors.textHint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text('discord.token_save'.tr()),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value != null) _accept(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('discord.web_login_title'.tr()),
        actions: [
          TextButton(
            onPressed: _paste,
            child: Text('discord.web_login_paste'.tr()),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
            initialSettings: InAppWebViewSettings(
              userAgent: _desktopUa,
              javaScriptEnabled: true,
              domStorageEnabled: true,
              // Nothing from this session outlives the screen. The token is
              // what gets kept, in the keystore — not a logged-in Discord.
              incognito: true,
              clearCache: true,
              thirdPartyCookiesEnabled: false,
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: _interceptor,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: _handler,
                callback: (args) {
                  if (args.isNotEmpty) _accept(args.first.toString());
                  return null;
                },
              );
            },
            onLoadStop: (controller, url) async {
              if (mounted && !_firstLoadDone) {
                setState(() => _firstLoadDone = true);
              }
              await controller.evaluateJavascript(source: _interceptor);
              await _tryGrab();
            },
          ),
          if (!_firstLoadDone)
            ColoredBox(
              color: AppColors.background,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
