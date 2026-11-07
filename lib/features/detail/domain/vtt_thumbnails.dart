/// One cue of a WebVTT thumbnail track: a picture, or a cell of a sprite sheet,
/// for a stretch of the video.
class VttThumbnail {
  final Duration start;
  final Duration end;
  final String imageUrl;
  final int x;
  final int y;
  final int w;
  final int h;

  const VttThumbnail({
    required this.start,
    required this.end,
    required this.imageUrl,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
  });

  bool get hasSprite => w > 0 && h > 0;

  bool contains(Duration position) => position >= start && position < end;
}

// WebVTT lets a cue under an hour leave the hours out (`01:30.000`), and
// generators do; requiring them dropped every such cue and the track with it.
final RegExp _cueTimes = RegExp(
  r'(?:(\d{2,}):)?(\d{2}):(\d{2})[\.,](\d{3})\s*-->\s*'
  r'(?:(\d{2,}):)?(\d{2}):(\d{2})[\.,](\d{3})',
);

Duration _timeOf(Match m, int group) => Duration(
  hours: int.parse(m.group(group) ?? '0'),
  minutes: int.parse(m.group(group + 1)!),
  seconds: int.parse(m.group(group + 2)!),
  milliseconds: int.parse(m.group(group + 3)!),
);

/// The cues of a thumbnail track, with image addresses resolved against
/// [baseUrl], the track's own address.
List<VttThumbnail> parseVttThumbnails(String vttBody, String baseUrl) {
  final lines = vttBody.split('\n').map((l) => l.trim()).toList();
  final results = <VttThumbnail>[];

  for (var i = 0; i < lines.length; i++) {
    final match = _cueTimes.firstMatch(lines[i]);
    if (match == null) continue;

    String? imageRef;
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].isNotEmpty) {
        imageRef = lines[j];
        break;
      }
    }
    if (imageRef == null) continue;

    var url = imageRef;
    var x = 0, y = 0, w = 0, h = 0;
    final hashIdx = imageRef.indexOf('#xywh=');
    if (hashIdx >= 0) {
      url = imageRef.substring(0, hashIdx);
      final coords = imageRef.substring(hashIdx + 6).split(',');
      if (coords.length == 4) {
        x = int.tryParse(coords[0]) ?? 0;
        y = int.tryParse(coords[1]) ?? 0;
        w = int.tryParse(coords[2]) ?? 0;
        h = int.tryParse(coords[3]) ?? 0;
      }
    }

    if (!url.startsWith('http')) {
      url = Uri.parse(baseUrl).resolve(url).toString();
    }

    results.add(
      VttThumbnail(
        start: _timeOf(match, 1),
        end: _timeOf(match, 5),
        imageUrl: url,
        x: x,
        y: y,
        w: w,
        h: h,
      ),
    );
  }
  return results;
}
