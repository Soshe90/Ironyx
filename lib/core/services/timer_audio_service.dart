import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The kinds of audio cue a timer session can emit.
enum TimerCue { countdown, transition, complete }

/// Audio cues for timer boundaries (ADR-4).
///
/// The service is owned at the container level so the same player is reused
/// for the whole session (ADR-4: "never construct a player per beep"). The
/// actual sound assets are not bundled yet, so the platform implementation
/// falls back to the system alert sound; drop real cue files into
/// `assets/audio/` and swap the cue bodies when they exist.
abstract interface class TimerAudioService {
  Future<void> preload();
  Future<void> cue(TimerCue cue);
  Future<void> dispose();
}

/// No-op implementation for web and tests.
class NoopTimerAudioService implements TimerAudioService {
  const NoopTimerAudioService();

  @override
  Future<void> preload() async {}

  @override
  Future<void> cue(TimerCue cue) async {}

  @override
  Future<void> dispose() async {}
}

/// Platform implementation. Uses the system alert sound as a minimal cue
/// until real audio assets are added.
class PlatformTimerAudioService implements TimerAudioService {
  AudioSession? _session;
  AudioSessionConfiguration? _configuration;

  @override
  Future<void> preload() async {
    try {
      final session = await AudioSession.instance;
      final configuration = const AudioSessionConfiguration.speech().copyWith(
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      );
      await session.configure(configuration);
      _session = session;
      _configuration = configuration;
    } on Object {
      // Audio-session configuration is best-effort on unsupported platforms.
    }
  }

  @override
  Future<void> cue(TimerCue cue) async {
    await preload();
    final session = _session;
    final configuration = _configuration;
    try {
      if (session != null) {
        await session.setActive(
          true,
          fallbackConfiguration:
              configuration ?? const AudioSessionConfiguration.speech(),
        );
      }
      await SystemSound.play(SystemSoundType.alert);
    } on MissingPluginException {
      // A device without an alert sound is not an error worth surfacing.
    } on Object {
      // Audio cues must never fail the timer.
    } finally {
      try {
        await session?.setActive(false);
      } on Object {
        // Ignore platform-specific deactivation failures.
      }
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _session?.setActive(false);
    } on Object {
      // Ignore platform-specific deactivation failures.
    }
    _session = null;
    _configuration = null;
  }
}

final Provider<TimerAudioService> timerAudioServiceProvider =
    Provider<TimerAudioService>(
  (ref) => kIsWeb ? const NoopTimerAudioService() : PlatformTimerAudioService(),
);
