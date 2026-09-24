// A chapter's translation group arrives with it from the host.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/data/models/episode_model.dart';

void main() {
  test('scanlator is read, and blank means none', () {
    expect(
      EpisodeModel.fromJson({
        'episode': 1,
        'label': 'Ch. 1',
        'mediaRef': 'x',
        'scanlator': 'Flame',
      }).scanlator,
      'Flame',
    );
    expect(
      EpisodeModel.fromJson({'episode': 1, 'label': '', 'mediaRef': ''})
          .scanlator,
      isNull,
    );
  });
}
