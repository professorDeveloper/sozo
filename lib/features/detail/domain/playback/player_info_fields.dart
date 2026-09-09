/// Which facts the player info overlay is allowed to show.
///
/// The overlay used to be one boolean: everything, or nothing. Everything is
/// fifteen rows stacked over the picture — useful once, while chasing a stutter,
/// and furniture every other time. Nothing is what people left it on, which made
/// the whole panel dead weight.
///
/// So it is a checklist. The interesting part is not the list; it is what
/// happens to a viewer's choices when the list itself changes in a later
/// release, which is the half that breaks silently.
///
/// Pure: ids in, ids out. No Flutter, no getIt, no I/O.
library;

/// One switchable row.
class PlayerInfoField {
  const PlayerInfoField({
    required this.id,
    required this.labelKey,
    required this.onByDefault,
  });

  /// Stable across releases — it is the storage key. See
  /// [PlayerInfoFields.fromStored] for why renaming one is not a cosmetic change.
  final String id;

  final String labelKey;

  /// Whether a viewer who has never opened this screen sees it.
  ///
  /// Deliberately not "all of them". The rows that are on by default are the
  /// ones that explain a complaint — what resolution actually arrived, which
  /// mirror served it, how far ahead the buffer is. The rest are for a bug
  /// report and are one tap away when somebody needs them.
  final bool onByDefault;
}

abstract final class PlayerInfoFields {
  static const List<PlayerInfoField> all = <PlayerInfoField>[
    PlayerInfoField(
      id: 'resolution',
      labelKey: 'player.info_resolution',
      onByDefault: true,
    ),
    PlayerInfoField(
      id: 'quality',
      labelKey: 'player.info_quality',
      onByDefault: true,
    ),
    PlayerInfoField(
      id: 'buffer',
      labelKey: 'player.info_buffer',
      onByDefault: true,
    ),
    PlayerInfoField(
      id: 'host',
      labelKey: 'player.info_host',
      onByDefault: true,
    ),
    PlayerInfoField(
      id: 'codec',
      labelKey: 'player.info_codec',
      onByDefault: true,
    ),
    PlayerInfoField(
      id: 'engine',
      labelKey: 'player.info_engine',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'provider',
      labelKey: 'player.info_provider',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'server',
      labelKey: 'player.info_server',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'hdr',
      labelKey: 'player.info_hdr',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'audio',
      labelKey: 'player.info_audio',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'container',
      labelKey: 'player.info_container',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'size',
      labelKey: 'player.info_size',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'position',
      labelKey: 'player.info_position',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'speed',
      labelKey: 'player.info_speed',
      onByDefault: false,
    ),
    PlayerInfoField(
      id: 'state',
      labelKey: 'player.info_state',
      onByDefault: false,
    ),
  ];

  static PlayerInfoField? byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// The set a viewer who has never opened the screen sees.
  static Set<String> get defaults =>
      {for (final f in all) if (f.onByDefault) f.id};

  /// Rebuilds the enabled set from storage.
  ///
  /// Storage is a map of EXPLICIT answers — `{id: on}` for every field the
  /// build that wrote it knew about — rather than a list of the enabled ones.
  /// That distinction is the whole point:
  ///
  /// With a list of enabled ids, "absent" means both *the viewer turned this
  /// off* and *this field did not exist when they last looked*. A field added
  /// later would then arrive switched off for everyone who had ever opened the
  /// screen, and there is nothing on screen to explain why one person's overlay
  /// has a row another's does not. With explicit answers, absent means new, and
  /// new takes [PlayerInfoField.onByDefault].
  ///
  /// A stored id that matches no field is dropped rather than kept as a ghost
  /// the checklist cannot draw.
  static Set<String> fromStored(Map<String, bool>? stored) {
    if (stored == null || stored.isEmpty) return defaults;
    final out = <String>{};
    for (final f in all) {
      final answer = stored[f.id];
      if (answer ?? f.onByDefault) out.add(f.id);
    }
    return out;
  }

  /// Explicit answers for every field this build knows about.
  static Map<String, bool> toStored(Set<String> enabled) =>
      {for (final f in all) f.id: enabled.contains(f.id)};

  /// Whether [enabled] is still what ships, which is what decides if Reset has
  /// anything to undo.
  static bool isDefault(Set<String> enabled) {
    final d = defaults;
    return enabled.length == d.length && enabled.containsAll(d);
  }
}
