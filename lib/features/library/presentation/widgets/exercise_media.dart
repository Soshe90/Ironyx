import 'package:flutter/material.dart';

import '../../../../core/database/tables/exercise_media.dart';
import '../../../../core/formatters/youtube.dart';

/// A curated image wins; a linked video is turned into a thumbnail
/// (already just a picture fallback — see `Youtube.searchUrl` for why a
/// specific video is never treated as "the" demo any more).
String? exercisePictureUrl(ExerciseMedia? media) {
  if (media == null) return null;
  if (media.type == ExerciseMediaType.video) {
    return Youtube.thumbnailUrl(media.url);
  }
  return media.url ?? media.localAsset;
}

IconData equipmentIcon(String equipmentId) => switch (equipmentId) {
      'barbell' => Icons.fitness_center,
      'dumbbell' => Icons.sports_gymnastics,
      'machine' => Icons.precision_manufacturing,
      'cable' => Icons.cable,
      'bodyweight' => Icons.accessibility_new,
      'kettlebell' => Icons.sports_kabaddi,
      'band' => Icons.linear_scale,
      'plate' => Icons.circle_outlined,
      'sled' => Icons.directions_run,
      _ => Icons.more_horiz,
    };

enum _ThumbState { loading, available, unavailable }

/// Exercise thumbnail with loading and error states.
///
/// YouTube doesn't 404 a `hqdefault.jpg` request for a video that's been
/// removed, made private, or never existed — it returns a 200 with a
/// fixed 120×90 grey placeholder instead. `errorBuilder` never fires for
/// that case, so it has to be detected by its distinctive size and treated
/// the same as a load failure: fall back to an icon, not a blurry grey box.
class ExerciseThumbnail extends StatefulWidget {
  const ExerciseThumbnail({
    required this.url,
    required this.fallbackIcon,
    this.fallbackUrl,
    super.key,
  });

  final String url;
  final String? fallbackUrl;
  final IconData fallbackIcon;

  @override
  State<ExerciseThumbnail> createState() => _ExerciseThumbnailState();
}

class _ExerciseThumbnailState extends State<ExerciseThumbnail> {
  static const int _placeholderWidth = 120;
  static const int _placeholderHeight = 90;

  late ImageProvider _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  _ThumbState _state = _ThumbState.loading;
  bool _usingFallback = false;

  ImageProvider _providerFor(String source) {
    final uri = Uri.tryParse(source);
    final isRemote =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    return isRemote ? NetworkImage(source) : AssetImage(source);
  }

  void _listenToProvider(String source) {
    _provider = _providerFor(source);
    _listener = ImageStreamListener(_onImage, onError: _onError);
    _stream = _provider.resolve(const ImageConfiguration())
      ..addListener(_listener!);
  }

  @override
  void initState() {
    super.initState();
    _listenToProvider(widget.url);
  }

  @override
  void didUpdateWidget(covariant ExerciseThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url &&
        oldWidget.fallbackUrl == widget.fallbackUrl) {
      return;
    }

    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _state = _ThumbState.loading;
    _usingFallback = false;
    _listenToProvider(widget.url);
  }

  void _tryFallback() {
    final fallbackUrl = widget.fallbackUrl;
    if (_usingFallback || fallbackUrl == null || fallbackUrl == widget.url) {
      if (mounted) setState(() => _state = _ThumbState.unavailable);
      return;
    }

    _usingFallback = true;
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    if (mounted) setState(() => _state = _ThumbState.loading);
    _listenToProvider(fallbackUrl);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final bool isMissingThumbnail = info.image.width == _placeholderWidth &&
        info.image.height == _placeholderHeight;
    if (isMissingThumbnail) {
      _tryFallback();
      return;
    }
    if (!mounted) return;
    setState(() => _state = _ThumbState.available);
  }

  void _onError(Object error, StackTrace? stackTrace) {
    _tryFallback();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: switch (_state) {
        _ThumbState.loading => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        _ThumbState.unavailable => Center(
            child: Icon(
              widget.fallbackIcon,
              color: scheme.onSurfaceVariant,
              size: 28,
            ),
          ),
        _ThumbState.available => Image(
            image: _provider,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
      },
    );
  }
}
