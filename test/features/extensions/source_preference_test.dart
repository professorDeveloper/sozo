// A JavaScript source's settings, read from the shapes Mangayomi declares
// and the LNReader adapter produces.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/extensions/domain/source_preference.dart';

void main() {
  test('each shape becomes its control, with the saved value winning', () {
    final list = [
      {
        'key': 'hide',
        'switchPreferenceCompat': {'title': 'Hide locked', 'value': false},
      },
      {
        'key': 'quality',
        'listPreference': {
          'title': 'Quality',
          'valueIndex': 1,
          'entries': ['480p', '720p', '1080p'],
          'entryValues': ['480', '720', '1080'],
        },
      },
      {
        'key': 'domain_url',
        'editTextPreference': {'title': 'Domain', 'value': 'https://a.test'},
      },
      {
        'key': 'langs',
        'multiSelectListPreference': {
          'title': 'Languages',
          'entries': ['English', 'French'],
          'entryValues': ['en', 'fr'],
          'values': ['en'],
        },
      },
      {'key': 'x', 'somethingElse': {}},
    ].map(SourcePreference.fromJson).toList();

    expect(list.last, isNull);
    final hide = list[0]! as SwitchSourcePreference;
    final quality = list[1]! as ListSourcePreference;
    final domain = list[2]! as TextSourcePreference;
    final langs = list[3]! as MultiSourcePreference;

    expect(hide.read(const {}), isFalse);
    expect(hide.read(const {'hide': true}), isTrue);
    expect(quality.read(const {}), '720');
    expect(quality.labelOf(quality.read(const {'quality': '1080'})), '1080p');
    // A saved value the source no longer offers falls back.
    expect(quality.read(const {'quality': '4k'}), '720');
    expect(domain.read(const {}), 'https://a.test');
    expect(langs.read(const {}), {'en'});
    expect(
      langs.read(const {
        'langs': ['fr'],
      }),
      {'fr'},
    );
  });
}
