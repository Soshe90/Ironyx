import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters/unit_formatters.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/responsive.dart';
import '../domain/timer_controller.dart';
import '../domain/timer_engine.dart';
import '../domain/timer_preset.dart';

/// Full-screen running timer (root route, ADR-3). The bottom bar is hidden so
/// a mid-set tap cannot dismiss the session accidentally.
class ActiveTimerPage extends ConsumerWidget {
  const ActiveTimerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TimerSnapshot?>(timerControllerProvider, (previous, next) {
      // The controller nulls its state once the session finishes or is ended.
      if (next == null && context.mounted) {
        context.pop();
      }
    });

    final TimerSnapshot? snapshot = ref.watch(timerControllerProvider);
    if (snapshot == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final TimerController controller =
        ref.read(timerControllerProvider.notifier);
    final bool denied = controller.notificationDenied;

    return Scaffold(
      appBar: AppBar(
        title: Text(controller.preset.name),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'End timer',
          onPressed: controller.stop,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: Column(
              children: [
                if (denied) const _PermissionDeniedBanner(),
                const Spacer(),
                _CountdownRing(snapshot: snapshot),
                const SizedBox(height: AppSpacing.xl),
                _PhaseLabel(snapshot: snapshot),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _intervalLabel(snapshot, controller.preset),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                _Controls(
                  isRunning: snapshot.isRunning,
                  onPause: controller.pause,
                  onResume: controller.resume,
                  onSkip: controller.skip,
                  onEnd: controller.stop,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _intervalLabel(TimerSnapshot snapshot, TimerPreset preset) {
    if (snapshot.isComplete) return 'Complete';
    final int current = snapshot.currentIndex + 1;
    return 'Interval $current of ${preset.totalIntervals}';
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.snapshot});

  final TimerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String countdown = UnitFormatters.duration(snapshot.remaining);

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: snapshot.progress,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          Text(
            countdown,
            style: AppTypography.countdown(scheme),
          ),
        ],
      ),
    );
  }
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({required this.snapshot});

  final TimerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final String label = snapshot.currentPhase?.type.label ?? 'Done';
    return Text(
      label,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.isRunning,
    required this.onPause,
    required this.onResume,
    required this.onSkip,
    required this.onEnd,
  });

  final bool isRunning;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSkip;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.skip_next),
          tooltip: 'Skip interval',
          onPressed: onSkip,
        ),
        const SizedBox(width: AppSpacing.xl),
        Semantics(
          button: true,
          label: isRunning ? 'Pause timer' : 'Resume timer',
          child: FilledButton(
            onPressed: isRunning ? onPause : onResume,
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 96),
              shape: const CircleBorder(),
            ),
            child: Icon(
              isRunning ? Icons.pause : Icons.play_arrow,
              size: 40,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        IconButton.filledTonal(
          icon: const Icon(Icons.stop),
          tooltip: 'End timer',
          onPressed: onEnd,
        ),
      ],
    );
  }
}

class _PermissionDeniedBanner extends StatefulWidget {
  const _PermissionDeniedBanner();

  @override
  State<_PermissionDeniedBanner> createState() =>
      _PermissionDeniedBannerState();
}

class _PermissionDeniedBannerState extends State<_PermissionDeniedBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Notifications are off — alerts will not fire if the app is '
              'fully backgrounded. The timer still runs.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: scheme.onErrorContainer),
            tooltip: 'Dismiss',
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
