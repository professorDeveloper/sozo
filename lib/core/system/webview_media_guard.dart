/// Keeps a hidden WebView's media hidden.
///
/// The headless WebViews that find a stream — and the ones that run
/// extensions — load real player pages with autoplay allowed, because some
/// only request their manifest once the video starts. On macOS a WebKit
/// video that plays out of sight is lifted into the system's
/// picture-in-picture window: the episode appeared floating over the app,
/// with its sound, after the player had closed. So every medium in those
/// pages is muted, refuses picture-in-picture, and is paused shortly after it
/// starts — by then the request that mattered has gone out.
const String kWebViewMediaGuard = r'''
(function(){
  if (window.__sozoMediaGuard) return;
  window.__sozoMediaGuard = true;
  function isMedia(m){ return m && m.tagName && /^(VIDEO|AUDIO)$/.test(m.tagName); }
  function quiet(m){
    try { m.muted = true; m.volume = 0; } catch (_) {}
    try { m.disablePictureInPicture = true; m.setAttribute('disablepictureinpicture', ''); } catch (_) {}
    try { m.removeAttribute('autopictureinpicture'); } catch (_) {}
  }
  document.addEventListener('play', function(e){ if (isMedia(e.target)) quiet(e.target); }, true);
  document.addEventListener('loadstart', function(e){ if (isMedia(e.target)) quiet(e.target); }, true);
  document.addEventListener('playing', function(e){
    var m = e.target;
    if (!isMedia(m)) return;
    quiet(m);
    setTimeout(function(){ try { m.pause(); } catch (_) {} }, 1500);
  }, true);
  document.addEventListener('enterpictureinpicture', function(){
    try { if (document.exitPictureInPicture) document.exitPictureInPicture(); } catch (_) {}
  }, true);
})();
''';
