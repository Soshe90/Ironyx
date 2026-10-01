import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters/unit_formatters.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/page_body.dart';
import '../domain/timer_controller.dart';
import '../domain/timer_engine.dart';
import '../domain/timer_preset.dart';
import 'timer_preset_labels.dart';

/// Full-screen running timer (root route, ADR-3). The bottom bar is hidden so
/// a mid-set tap cannot dismiss the session accidentally.
class ActiveTimerPage extends ConsumerWidget {
  const ActiveTimerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TimerSnapshot?>(timerControllerProvider, (previous, next) {
      // The controller nulls its state once the session finishes or is ended.
      if (next == null && context.mounted) {
        // An end-confirmation dialog may still be open if the last interval
        // ran out under it; close it first, or this pop would close the
        // dialog and leave the page spinning on a null session.
        Navigator.of(context).popUntil((Route<dynamic> r) => r is! PopupRoute);
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
    final Color phaseColor = _phaseColor(
      Theme.of(context),
      snapshot.currentPhase?.type,
    );

    // Ending is one tap on a phone held mid-set, and system back used to
    // pop this screen while the session kept running with no way back to
    // it. Every exit now goes through the same confirmation. The
    // controller's own pop on finish uses `Navigator.pop`, which a
    // PopScope does not block.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) unawaited(_confirmEnd(context, controller));
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(controller.preset.displayName(context.l10n)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.l10n.timerEndTooltip,
            onPressed: () => _confirmEnd(context, controller),
          ),
        ),
        body: SafeArea(
          child: PageBody(
            // One tween drives the ring and the label so they change hue
            // together at a phase boundary.
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: phaseColor),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppDuration.normal,
              builder: (BuildContext context, Color? color, _) => Column(
                children: [
                  if (denied) const _PermissionDeniedBanner(),
                  // The interval counter is context for the countdown, so it
                  // reads above it as an eyebrow rather than as a footnote.
                  const Spacer(),
                  Text(
                    _intervalLabel(context, snapshot, controller.preset)
                        .toUpperCase(),
                    style: AppTypography.eyebrow(Theme.of(context)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Flexible(
                    flex: _ringFlex,
                    child: _CountdownRing(
                      snapshot: snapshot,
                      color: color ?? phaseColor,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _PhaseLabel(snapshot: snapshot, color: color ?? phaseColor),
                  const Spacer(),
                  _Controls(
                    isRunning: snapshot.isRunning,
                    onPause: controller.pause,
                    onResume: controller.resume,
                    onSkip: controller.skip,
                    onEnd: () => _confirmEnd(context, controller),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmEnd(
    BuildContext context,
    TimerController controller,
  ) async {
    final bool? end = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.timerEndConfirmTitle),
        content: Text(context.l10n.timerEndConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.timerEndConfirmAction),
          ),
        ],
      ),
    );
    // Not gated on `context.mounted`: if the session finished on its own
    // while the dialog was open, `stop` on an idle controller is harmless,
    // and the user did ask for it to end.
    if (end == true && controller.isActive) await controller.stop();
  }

  String _intervalLabel(
    BuildContext context,
    TimerSnapshot snapshot,
    TimerPreset preset,
  ) {
    final AppLocalizations l10n = context.l10n;
    if (snapshot.isComplete) return l10n.timerComplete;
    return l10n.timerIntervalOf(
      snapshot.currentIndex + 1,
      preset.totalIntervals,
    );
  }
}

/// Cap for the countdown ring. It fills the shorter side of the space it is
/// given, so the timer stays glanceable on a phone and does not look lost on
/// a tablet, but never grows past the point where the digits outrun the
/// ring. There is deliberately no minimum: a floor larger than the height
/// available was squashed by the layout into an oval (seen on a real phone).
const double _ringMaxDiameter = 360;

/// Share of the free vertical space given to the ring, against one share
/// for each spacer above and below. At an even split the ring, the thing
/// people glance at mid-set, got only a third of the room.
const int _ringFlex = 4;
const double _ringStrokeWidth = 10;

/// Fraction of the ring's diameter given to the countdown digits.
const double _countdownScale = 0.26;

/// The hue of a phase. Work keeps the brand primary; the rest come from
/// [AppColors]. A finished session (no phase) falls back to primary.
Color _phaseColor(ThemeData theme, TimerPhaseType? type) {
  final bool dark = theme.brightness == Brightness.dark;
  return switch (type) {
    TimerPhaseType.rest =>
      dark ? AppColors.phaseRestDark : AppColors.phaseRestLight,
    TimerPhaseType.prepare =>
      dark ? AppColors.phasePrepareDark : AppColors.phasePrepareLight,
    TimerPhaseType.cooldown =>
      dark ? AppColors.phaseCooldownDark : AppColors.phaseCooldownLight,
    TimerPhaseType.work || null => theme.colorScheme.primary,
  };
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.snapshot, required this.color});

  final TimerSnapshot snapshot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String countdown =
        UnitFormatters.durationRoundedUp(snapshot.remaining);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.biggest.shortestSide;
        final double diameter =
            available < _ringMaxDiameter ? available : _ringMaxDiameter;

        return Center(
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: snapshot.progress,
                    strokeWidth: _ringStrokeWidth,
                    strokeCap: StrokeCap.round,
                    color: color,
                    // A tint of the phase colour, so the whole ring reads
                    // as the phase even when little time is left.
                    backgroundColor: Color.alphaBlend(
                      color.withValues(alpha: 0.16),
                      scheme.surface,
                    ),
                  ),
                ),
                Text(
                  countdown,
                  style: AppTypography.countdown(
                    scheme,
                    size: diameter * _countdownScale,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({required this.snapshot, required this.color});

  final TimerSnapshot snapshot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String label =
        snapshot.currentPhase?.type.label(l10n) ?? l10n.timerPhaseDone;
    return Text(
      label,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
    );
  }
}

/// Pause/resume is the control reached for mid-set, often without looking,
/// so it is deliberately far larger than the accessibility floor.
const double _primaryControlSize = 96;
const double _primaryControlIconSize = 40;

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
          tooltip: context.l10n.timerSkipTooltip,
          onPressed: onSkip,
        ),
        const SizedBox(width: AppSpacing.xl),
        Semantics(
          button: true,
          label: isRunning
              ? context.l10n.timerPauseSemantic
              : context.l10n.timerResumeSemantic,
          child: FilledButton(
            onPressed: isRunning ? onPause : onResume,
            style: FilledButton.styleFrom(
              minimumSize: const Size(_primaryControlSize, _primaryControlSize),
              shape: const CircleBorder(),
            ),
            child: Icon(
              isRunning ? Icons.pause : Icons.play_arrow,
              size: _primaryControlIconSize,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        IconButton.filledTonal(
          icon: const Icon(Icons.stop),
          tooltip: context.l10n.timerEndTooltip,
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
              context.l10n.timerNotificationsOff,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: scheme.onErrorContainer),
            tooltip: context.l10n.actionClose,
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
