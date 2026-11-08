/// The SF Symbol each player control wears on the native glass bars, keyed by
/// the control's id (`PlayerControlCatalogue`) and the player's own pieces.
///
/// Apple's own where Apple's players have one (AVKit: `gobackward.10`,
/// `gauge.with.dots.needle.67percent`, `pip.enter`, `captions.bubble`), the
/// nearest standard symbol elsewhere. Every name is checked against the
/// phone's own list in test/core/native/sf_symbols_test.dart.
const Map<String, String> playerSymbols = {
  'back': 'chevron.backward',
  'language': 'character.bubble',
  'subtitles': 'captions.bubble',
  'settings': 'gearshape',
  'orientation': 'rectangle.portrait.rotate',
  'lock': 'lock.fill',
  'unlock': 'lock.open.fill',
  'stats': 'info.circle',
  'speed': 'gauge.with.dots.needle.67percent',
  'server': 'server.rack',
  'quality': 'slider.horizontal.3',
  'episodes': 'rectangle.stack',
  'previous': 'backward.end.fill',
  'next': 'forward.end.fill',
  'shader': 'sparkles',
  'fit': 'aspectratio',
  'sleep': 'moon.zzz',
  'cast': 'tv.badge.wifi',
  'party': 'person.2',
  'pip': 'pip.enter',
  'download': 'arrow.down.circle',
  'rewind': 'gobackward',
  'forward': 'goforward',
  'play': 'play.fill',
  'pause': 'pause.fill',
  'replay': 'arrow.counterclockwise',
  'react': 'face.smiling',
  'comments': 'bubble.left.and.bubble.right',
  'skip': 'forward.fill',
  'more': 'ellipsis.circle',
};

/// The filled face of a control while it is on.
const Map<String, String> activeSymbols = {
  'subtitles': 'captions.bubble.fill',
  'stats': 'info.circle.fill',
  'sleep': 'moon.zzz.fill',
  'download': 'arrow.down.circle.fill',
  'party': 'person.2.fill',
  'cast': 'tv.badge.wifi.fill',
};

/// [id]'s symbol, its filled face when [active] and it has one.
String playerSymbol(String id, {bool active = false}) =>
    (active ? activeSymbols[id] : null) ?? playerSymbols[id] ?? 'circle';

/// The rotate button names the turn it makes: the phone upright turns to
/// landscape, and back.
String orientationSymbol({required bool portrait}) =>
    portrait ? 'rectangle.portrait.rotate' : 'rectangle.landscape.rotate';

/// The step lengths SF Symbols draws a number into.
const Set<int> _numberedSteps = {5, 10, 15, 30, 45, 60, 75, 90};

String rewindSymbol(int s) =>
    _numberedSteps.contains(s) ? 'gobackward.$s' : 'gobackward';

String forwardSymbol(int s) =>
    _numberedSteps.contains(s) ? 'goforward.$s' : 'goforward';
