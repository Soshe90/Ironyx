import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/services/timer_audio_service.dart';

/// Records what the service asks of a player, with switches to make each
/// step fail, so the service's behaviour is testable without `just_audio`'s
/// platform channel.
class _FakePlayer implements TimerCuePlayer {
  _FakePlayer(this.log, {this.failLoad = false, this.failPlay = false});

  final List<String> log;
  final bool failLoad;
  final bool failPlay;
  String? asset;
  int plays = 0;
  bool disposed = false;

  @override
  Future<void> load(String assetPath) async {
    if (failLoad) throw StateError('cannot decode $assetPath');
    asset = assetPath;
    log.add('load $assetPath');
  }

  @override
  Future<void> play() async {
    if (failPlay) throw StateError('cannot play $asset');
    plays++;
    log.add('play $asset');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    log.add('dispose $asset');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> log;
  late List<_FakePlayer> created;
  late int alerts;

  /// Builds a service whose players are fakes; [configure] can make specific
  /// players (by creation order) misbehave.
  PlatformTimerAudioService build({
    _FakePlayer Function(int index)? configure,
  }) {
    return PlatformTimerAudioService(
      playerFactory: () {
        final _FakePlayer player =
            configure?.call(created.length) ?? _FakePlayer(log);
        created.add(player);
        return player;
      },
      systemAlert: () async => alerts++,
    );
  }

  setUp(() {
    log = <String>[];
    created = <_FakePlayer>[];
    alerts = 0;
  });

  group('bundled cue files', () {
    test('every cue has an asset that exists and is a WAV', () {
      expect(timerCueAssets.keys, containsAll(TimerCue.values));
      for (final MapEntry<TimerCue, String> entry in timerCueAssets.entries) {
        final File file = File(entry.value);
        expect(file.existsSync(), isTrue, reason: '${entry.value} is missing');
        final List<int> header = file.readAsBytesSync().sublist(0, 12);
        expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
      }
    });
  });

  group('preload', () {
    test('loads each cue once, into its own player', () async {
      final PlatformTimerAudioService service = build();

      await service.preload();

      expect(created, hasLength(TimerCue.values.length));
      expect(
        created.map((p) => p.asset),
        unorderedEquals(timerCueAssets.values),
      );
    });

    test('is idempotent: repeated preloads and cues create no new players',
        () async {
      final PlatformTimerAudioService service = build();

      await service.preload();
      await service.preload();
      await service.cue(TimerCue.countdown);
      await service.cue(TimerCue.countdown);

      // ADR-4: never construct a player per beep.
      expect(created, hasLength(TimerCue.values.length));
    });
  });

  group('cue', () {
    test('plays the file for that cue, and only that one', () async {
      final PlatformTimerAudioService service = build();

      await service.cue(TimerCue.transition);

      final Iterable<String> played =
          log.where((String line) => line.startsWith('play '));
      expect(played, <String>[
        'play ${timerCueAssets[TimerCue.transition]}',
      ]);
      expect(alerts, 0, reason: 'no fallback when the file plays');
    });

    test('reuses the same player on every play of a cue', () async {
      final PlatformTimerAudioService service = build();

      await service.cue(TimerCue.countdown);
      await service.cue(TimerCue.countdown);
      await service.cue(TimerCue.countdown);

      final _FakePlayer countdown = created.singleWhere(
        (p) => p.asset == timerCueAssets[TimerCue.countdown],
      );
      expect(countdown.plays, 3);
    });

    test('falls back to the system alert when a cue fails to load', () async {
      // The first player created (countdown) cannot decode its file.
      final PlatformTimerAudioService service = build(
        configure: (int i) => _FakePlayer(log, failLoad: i == 0),
      );

      await service.cue(TimerCue.countdown);
      await service.cue(TimerCue.transition);

      expect(alerts, 1, reason: 'only the broken cue falls back');
      expect(
        log.where((l) => l.startsWith('play ')),
        <String>['play ${timerCueAssets[TimerCue.transition]}'],
      );
    });

    test('falls back to the system alert when no player can be created',
        () async {
      final PlatformTimerAudioService service = PlatformTimerAudioService(
        playerFactory: () => throw StateError('no audio plugin'),
        systemAlert: () async => alerts++,
      );

      await expectLater(service.cue(TimerCue.complete), completes);

      expect(alerts, 1);
    });

    test('never throws when playback itself fails', () async {
      final PlatformTimerAudioService service = build(
        configure: (int i) => _FakePlayer(log, failPlay: true),
      );

      await expectLater(service.cue(TimerCue.countdown), completes);
      await expectLater(service.cue(TimerCue.complete), completes);
    });

    test('never throws when the system alert itself fails', () async {
      final PlatformTimerAudioService service = PlatformTimerAudioService(
        playerFactory: () => throw StateError('no audio plugin'),
        systemAlert: () async => throw StateError('no alert sound'),
      );

      await expectLater(service.cue(TimerCue.complete), completes);
    });
  });

  group('dispose', () {
    test('disposes every player that was created', () async {
      final PlatformTimerAudioService service = build();
      await service.preload();

      await service.dispose();

      expect(created, isNotEmpty);
      expect(created.every((p) => p.disposed), isTrue);
    });

    test('the service can be reused for the next session', () async {
      final PlatformTimerAudioService service = build();
      await service.cue(TimerCue.countdown);
      await service.dispose();
      final int afterFirstSession = created.length;

      await service.cue(TimerCue.countdown);

      expect(created.length, afterFirstSession + TimerCue.values.length);
      expect(created.last.disposed, isFalse);
      expect(alerts, 0);
    });

    test('a player that fails to dispose does not break dispose', () async {
      final PlatformTimerAudioService service = PlatformTimerAudioService(
        playerFactory: () => _ThrowingDisposePlayer(),
        systemAlert: () async => alerts++,
      );
      await service.preload();

      await expectLater(service.dispose(), completes);
    });
  });
}

class _ThrowingDisposePlayer implements TimerCuePlayer {
  @override
  Future<void> load(String assetPath) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> dispose() async => throw StateError('will not dispose');
}
