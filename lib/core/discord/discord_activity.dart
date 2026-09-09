import 'package:flutter/foundation.dart';

/// What Sozo tells Discord somebody is doing.
///
/// Deliberately a plain value with no notion of Discord's wire format — both
/// transports (the desktop IPC socket and the mobile gateway) serialise it
/// their own way, and the player that produces one should not have to know
/// which is connected.
@immutable
class DiscordActivity {
  const DiscordActivity({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.imageText,
    this.startedAt,
    this.endsAt,
    this.watchUrl,
  });

  /// The film or series name. The first line Discord shows.
  final String title;

  /// Episode, season, or the source. The second line.
  final String? subtitle;

  /// Poster art.
  ///
  /// Discord's IPC only accepts a KEY of an asset uploaded to the developer
  /// portal, not an arbitrary url — the gateway accepts `mp:external/...`
  /// proxied urls. Each transport handles that difference; this just carries
  /// what the app has.
  final String? imageUrl;

  /// Tooltip on the art. Usually the source name.
  final String? imageText;

  /// When playback of the CURRENT position started, in wall-clock terms.
  ///
  /// Discord renders elapsed time from this, so it is not the moment the
  /// episode began — it is now minus the current position. Seeking changes it.
  final DateTime? startedAt;

  /// When the episode would finish at the current position. Discord shows a
  /// countdown from this when both ends are present.
  final DateTime? endsAt;

  /// Where the title can be opened. Becomes a button.
  final String? watchUrl;

  /// Whether two activities differ in a way Discord would render.
  ///
  /// Presence updates are rate limited — Discord allows roughly one every 15
  /// seconds per connection and drops the rest — so a player that ticks four
  /// times a second must not send four updates a second. Position is
  /// deliberately NOT compared: it moves constantly and Discord derives the
  /// elapsed bar from the timestamps by itself.
  bool sameAs(DiscordActivity? other) =>
      other != null &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.imageUrl == imageUrl &&
      other.imageText == imageText &&
      other.watchUrl == watchUrl;

  DiscordActivity copyWith({DateTime? startedAt, DateTime? endsAt}) =>
      DiscordActivity(
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        imageText: imageText,
        startedAt: startedAt ?? this.startedAt,
        endsAt: endsAt ?? this.endsAt,
        watchUrl: watchUrl,
      );
}
