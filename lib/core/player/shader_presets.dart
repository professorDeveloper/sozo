/// Anime4K — GLSL upscaling, applied by libmpv while the episode plays.
///
/// ## What this actually does
///
/// Anime4K (bloc97, MIT) is a set of small convolutional networks written as
/// GLSL fragment shaders. mpv runs them between decode and display, so a 720p
/// source is restored and upscaled on the GPU in real time. On animation the
/// difference is large and obvious — line art is what these networks were
/// trained on — which is exactly why this is worth having in an app whose
/// catalogue is mostly anime, and why it is a poor fit for live action.
///
/// ## Why the files are downloaded and not bundled
///
/// The full set is around a megabyte of shader source per chain, and most
/// people will never turn this on. Bundling it would tax every install for a
/// feature a minority uses; fetching on first use costs one download, once,
/// from the project's own repository.
///
/// ## Why there is a tier and not a single "on"
///
/// The VL networks are roughly four times the work of the M ones and will not
/// hold sixty frames a second on a mid-range phone — and a preset that drops
/// frames looks worse than no preset at all, while appearing to be the "better"
/// setting. Splitting the choice makes the trade visible instead of hiding a
/// cliff inside one switch.
///
/// ## Where it does not apply
///
/// libmpv only. The platform player cannot load shaders at all.
library;

/// One named look, and the chain that produces it.
class ShaderPreset {
  const ShaderPreset(this.id, this.labelKey, this.descriptionKey, this._chains);

  /// Persisted in Hive. Never rename one.
  final String id;
  final String labelKey;
  final String descriptionKey;

  /// tier id -> the shader files, in the order mpv must run them.
  final Map<String, List<String>> _chains;

  /// Nothing to download and nothing to run.
  bool get isOff => _chains.isEmpty;

  /// The files this preset needs at [tier], in order.
  List<String> chainFor(String tier) =>
      _chains[tier] ?? _chains[ShaderTier.mid.id] ?? const [];

  static const ShaderPreset off =
      ShaderPreset('off', 'player.shader_off', 'player.shader_off_desc', {});

  static const List<ShaderPreset> all = [
    off,

    // Restore then upscale: the default Anime4K recommendation, and the one
    // that helps most sources. Sharpens line art without inventing edges.
    ShaderPreset(
      'sharpen',
      'player.shader_sharpen',
      'player.shader_sharpen_desc',
      {
        'mid': [
          'Restore/Anime4K_Clamp_Highlights.glsl',
          'Restore/Anime4K_Restore_CNN_M.glsl',
          'Upscale/Anime4K_Upscale_CNN_x2_M.glsl',
        ],
        'high': [
          'Restore/Anime4K_Clamp_Highlights.glsl',
          'Restore/Anime4K_Restore_CNN_VL.glsl',
          'Upscale/Anime4K_Upscale_CNN_x2_VL.glsl',
        ],
      },
    ),

    // The "Soft" restore networks. For sources that are blurry rather than
    // merely low-resolution, where the sharpening chain above amplifies the
    // blur's own artefacts along with the detail.
    ShaderPreset(
      'deblur',
      'player.shader_deblur',
      'player.shader_deblur_desc',
      {
        'mid': [
          'Restore/Anime4K_Clamp_Highlights.glsl',
          'Restore/Anime4K_Restore_CNN_Soft_M.glsl',
          'Upscale/Anime4K_Upscale_CNN_x2_M.glsl',
        ],
        'high': [
          'Restore/Anime4K_Clamp_Highlights.glsl',
          'Restore/Anime4K_Restore_CNN_Soft_VL.glsl',
          'Upscale/Anime4K_Upscale_CNN_x2_VL.glsl',
        ],
      },
    ),

    // Upscale and denoise in one pass, for heavily compressed sources where
    // the banding and blocking would otherwise be sharpened too.
    ShaderPreset(
      'denoise',
      'player.shader_denoise',
      'player.shader_denoise_desc',
      {
        'mid': [
          'Restore/Anime4K_Clamp_Highlights.glsl',
          'Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
        ],
        'high': [
          'Restore/Anime4K_Clamp_Highlights.glsl',
          'Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl',
        ],
      },
    ),
  ];

  static ShaderPreset fromId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return off;
  }

  /// Every file any preset can ask for, deduplicated — what a "download all"
  /// would fetch, and what a cache cleanup may delete.
  static Set<String> get allFiles => {
        for (final p in all)
          for (final chain in p._chains.values) ...chain,
      };
}

/// How much GPU the chain is allowed to cost.
enum ShaderTier {
  /// The M networks. Smooth on most phones.
  mid('mid', 'player.shader_tier_mid', 'player.shader_tier_mid_desc'),

  /// The VL networks — roughly four times the work, and worth it only on a
  /// GPU that can hold the frame rate.
  high('high', 'player.shader_tier_high', 'player.shader_tier_high_desc');

  const ShaderTier(this.id, this.labelKey, this.descriptionKey);

  final String id;
  final String labelKey;
  final String descriptionKey;

  static ShaderTier fromId(String? id) =>
      id == high.id ? high : mid;
}
