import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/youtube.dart';

void main() {
  group('Youtube.videoId / thumbnailUrl', () {
    test('extracts the id from a watch URL', () {
      expect(
        Youtube.videoId('https://www.youtube.com/watch?v=rT7DgCr-3pg'),
        'rT7DgCr-3pg',
      );
    });

    test('extracts the id from a Shorts URL', () {
      expect(
        Youtube.videoId('https://www.youtube.com/shorts/O2J8Qs7Wl3U'),
        'O2J8Qs7Wl3U',
      );
    });

    test('extracts the id from a youtu.be short link', () {
      expect(Youtube.videoId('https://youtu.be/rT7DgCr-3pg'), 'rT7DgCr-3pg');
    });

    test('returns null for a non-YouTube or malformed URL', () {
      expect(Youtube.videoId('https://example.com/video'), isNull);
      expect(Youtube.videoId(null), isNull);
    });

    test('thumbnailUrl builds the hqdefault CDN URL', () {
      expect(
        Youtube.thumbnailUrl('https://www.youtube.com/shorts/O2J8Qs7Wl3U'),
        'https://img.youtube.com/vi/O2J8Qs7Wl3U/hqdefault.jpg',
      );
      expect(Youtube.thumbnailUrl(null), isNull);
    });
  });

  group('Youtube.searchUrl', () {
    test('builds a results search, never a specific video', () {
      final uri = Youtube.searchUrl('Rear Delt Fly (Machine)');
      expect(uri.host, 'www.youtube.com');
      expect(uri.path, '/results');
      expect(
        uri.queryParameters['search_query'],
        'Rear Delt Fly (Machine) exercise tutorial',
      );
    });
  });
}
