import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/network/user_agent.dart';
import 'package:soplay/features/download/data/repositories/download_repository_impl.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';

void main() {
  DownloadItem item({
    required DownloadKind kind,
    String url = 'https://cdn.example.net/v/index.m3u8',
    Map<String, String> headers = const {},
  }) => DownloadItem(
    id: 'id',
    contentUrl: '/title',
    provider: 'anikoto',
    title: 'Title',
    sourceUrl: url,
    relativePath: 'downloads/id/index.m3u8',
    createdAt: 1,
    kind: kind,
    headers: headers,
  );

  test('a video transfer carries the agent the player plays it with', () {
    for (final kind in [DownloadKind.hls, DownloadKind.video]) {
      final row = item(
        kind: kind,
        headers: const {'Referer': 'https://megaplay.example/'},
      );
      final headers = DownloadRepositoryImpl.transferHeaders(row);
      expect(headers['User-Agent'], kSozoUserAgent);
      expect(headers['Referer'], 'https://megaplay.example/');
      expect(headers['Sec-Fetch-Site'], 'cross-site');
      // Computed for the request, not written back to the row.
      expect(row.headers, {'Referer': 'https://megaplay.example/'});
    }
  });

  test('an agent the source chose is kept', () {
    final headers = DownloadRepositoryImpl.transferHeaders(
      item(kind: DownloadKind.video, headers: const {'User-Agent': 'CS/1.0'}),
    );
    expect(headers['User-Agent'], 'CS/1.0');
  });

  test('chapters and loopback urls keep their own headers', () {
    const own = {'Referer': 'https://reader.example/'};
    expect(
      DownloadRepositoryImpl.transferHeaders(
        item(kind: DownloadKind.manga, headers: own),
      ),
      own,
    );
    expect(
      DownloadRepositoryImpl.transferHeaders(
        item(
          kind: DownloadKind.hls,
          url: 'http://127.0.0.1:4100/p/t/https/cdn/x.m3u8',
          headers: own,
        ),
      ),
      own,
    );
  });
}
