/// Helpers for linking out to YouTube from an exercise.
///
/// Curating one specific demo video per exercise has repeatedly proven
/// fragile — wrong postures, removed/private videos, YouTube's silent
/// placeholder thumbnail for a dead link. "Watch a demo" always sends the
/// user to a YouTube *search* for the exercise name instead: it can't go
/// stale or point at the wrong movement, at the cost of not being a single
/// curated video. [thumbnailUrl] is unaffected — it's still a fine picture
/// fallback for exercises without a curated [imageUrl] on the model.
abstract final class Youtube {
  static final RegExp _idPattern = RegExp(
    r'(?:youtu\.be/|youtube\.com/(?:watch\?v=|embed/|shorts/))([\w-]{11})',
  );

  static String? videoId(String? videoUrl) {
    if (videoUrl == null) return null;
    return _idPattern.firstMatch(videoUrl)?.group(1);
  }

  /// A `hqdefault` thumbnail — available for every public video, no API key.
  static String? thumbnailUrl(String? videoUrl) {
    final id = videoId(videoUrl);
    return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }

  /// A YouTube search-results link for [exerciseName] — never a specific
  /// video, so it's always relevant and never dead.
  static Uri searchUrl(String exerciseName) => Uri.https(
        'www.youtube.com',
        '/results',
        {'search_query': '$exerciseName exercise tutorial'},
      );
}
