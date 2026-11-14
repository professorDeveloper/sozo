import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/downloaded_title.dart';
import 'package:soplay/features/download/domain/entities/offline_title.dart';
import 'package:soplay/features/download/presentation/pages/downloads_page.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';

DownloadedTitle _title(String provider, {String? savedName}) => DownloadedTitle(
  key: 'k',
  lead: DownloadItem(
    id: 'a',
    contentUrl: 'page',
    provider: provider,
    title: 'Film',
    sourceUrl: 'video',
    relativePath: 'downloads/a/video.mp4',
    createdAt: 0,
  ),
  completed: 1,
  total: 1,
  sizeBytes: 1,
  lastAt: 0,
  snapshot: savedName == null
      ? null
      : OfflineTitle(
          contentUrl: 'page',
          provider: provider,
          providerName: savedName,
          title: 'Film',
          savedAt: 1,
        ),
);

ProviderEntity _live(String id, String name) => ProviderEntity(
  id: id,
  name: name,
  image: '',
  url: '',
  description: '',
  domains: const [],
);

void main() {
  test('a renamed source shows its current name, not the saved one', () {
    expect(
      downloadSourceName(_title('vidapi', savedName: 'VidAPI'), [
        _live('vidapi', 'VixSrc'),
      ]),
      'VixSrc',
    );
  });

  test('a source no longer installed keeps the name it was saved under', () {
    expect(
      downloadSourceName(_title('vidapi', savedName: 'VidAPI'), const []),
      'VidAPI',
    );
  });

  test('with no saved name and no source, the bare id is shown', () {
    expect(downloadSourceName(_title('cs:moviebox'), const []), 'moviebox');
  });
}
