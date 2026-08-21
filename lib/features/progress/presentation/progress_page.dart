import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';

const _uuid = Uuid();

/// Progress and analytics hub.
class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  String? _exerciseId;
  int? _rangeDays = 90;

  static DateTime? _sinceFor(int? rangeDays) =>
      rangeDays == null ? null : DateTime.now().subtract(Duration(days: rangeDays));

  static String _rangeLabel(int? rangeDays) => switch (rangeDays) {
        30 => '1M',
        90 => '3M',
        365 => '1Y',
        null => 'All',
        _ => '$rangeDays d',
      };

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(allExercisesStreamProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Estimated 1RM'),
          exercises.when(
            data: (items) {
              if (items.isEmpty) {
                return const _ChartEmpty(
                  icon: Icons.show_chart,
                  message: 'Complete weighted sets to see strength trends.',
                );
              }
              final selected =
                  items.any((item) => item.exercise.id == _exerciseId)
                      ? _exerciseId
                      : items.first.exercise.id;
              if (_exerciseId != selected) {
                _exerciseId = selected;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selected,
                          decoration:
                              const InputDecoration(labelText: 'Exercise'),
                          items: [
                            for (final item in items)
                              DropdownMenuItem(
                                value: item.exercise.id,
                                child: Text(item.exercise.name),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _exerciseId = value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<int?>(
                          initialValue: _rangeDays,
                          decoration: const InputDecoration(labelText: 'Range'),
                          items: const [
                            DropdownMenuItem(value: 30, child: Text('1M')),
                            DropdownMenuItem(value: 90, child: Text('3M')),
                            DropdownMenuItem(value: 365, child: Text('1Y')),
                            DropdownMenuItem(value: null, child: Text('All')),
                          ],
                          onChanged: (value) =>
                              setState(() => _rangeDays = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<OneRMSeriesPoint>>(
                    stream: ref.read(workoutDaoProvider).watchOneRMSeries(
                          selected!,
                          since: _sinceFor(_rangeDays),
                        ),
                    builder: (context, snapshot) => _OneRmChart(
                      points: snapshot.data ?? const [],
                      loading:
                          snapshot.connectionState == ConnectionState.waiting,
                      unit: unit,
                    ),
                  ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('Unable to load exercises: $error'),
          ),
          const SizedBox(height: 24),
          _SectionTitle('Weekly volume (${_rangeLabel(_rangeDays)})'),
          StreamBuilder<List<WeeklyVolume>>(
            stream: ref.read(workoutDaoProvider).watchWeeklyVolume(
                  since: _sinceFor(_rangeDays),
                ),
            builder: (context, snapshot) => _VolumeChart(
              points: snapshot.data ?? const [],
              loading: snapshot.connectionState == ConnectionState.waiting,
              unit: unit,
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle('Workout frequency (${_rangeLabel(_rangeDays)})'),
          _WorkoutFrequencySection(
            stream: ref.read(workoutDaoProvider).watchWorkoutFrequency(
                  since: _sinceFor(_rangeDays),
                ),
          ),
          const SizedBox(height: 24),
          _SectionTitle('Volume by muscle group (${_rangeLabel(_rangeDays)})'),
          StreamBuilder<List<MuscleGroupVolume>>(
            stream: ref.read(workoutDaoProvider).watchMuscleGroupVolume(
                  since: _sinceFor(_rangeDays),
                ),
            builder: (context, snapshot) => _MuscleGroupChart(
              points: snapshot.data ?? const [],
              loading: snapshot.connectionState == ConnectionState.waiting,
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Body metrics'),
          const _BodyMetricsSection(),
        ],
      ),
    );
  }
}

class _WorkoutFrequencySection extends StatelessWidget {
  const _WorkoutFrequencySection({required this.stream});

  final Stream<List<WorkoutFrequency>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WorkoutFrequency>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        final points = snapshot.data ?? const <WorkoutFrequency>[];
        if (points.isEmpty) {
          return const _ChartEmpty(
            icon: Icons.event_available_outlined,
            message: 'Complete workouts to see your weekly frequency.',
          );
        }
        final total = points.fold<int>(
          0,
          (sum, point) => sum + point.workoutCount,
        );
        final average = total / points.length;
        return AppCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$total workout${total == 1 ? '' : 's'} in the last '
                  '${points.length} active week${points.length == 1 ? '' : 's'}',
                ),
              ),
              Text(
                '${average.toStringAsFixed(1)} / week',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BodyMetricsSection extends ConsumerWidget {
  const _BodyMetricsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<BodyMetrics>>(
      stream: ref.read(bodyMetricsDaoProvider).watchAll(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <BodyMetrics>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Log measurement'),
              ),
            ),
            if (entries.length >= 2) _BodyWeightChart(entries: entries),
            if (entries.isEmpty)
              const _ChartEmpty(
                icon: Icons.monitor_weight_outlined,
                message: 'Track weight and body fat over time.',
              )
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AppCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${entry.weightKg.toStringAsFixed(1)} kg'),
                      subtitle: Text(
                        '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}-${entry.date.day.toString().padLeft(2, '0')}'
                        '${entry.bodyFatPercentage == null ? '' : ' · ${entry.bodyFatPercentage!.toStringAsFixed(1)}% body fat'}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') {
                            _edit(context, ref, entry: entry);
                          }
                          if (action == 'delete') {
                            ref
                                .read(bodyMetricsDaoProvider)
                                .deleteByDate(entry.date);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    BodyMetrics? entry,
  }) async {
    final weight =
        TextEditingController(text: entry?.weightKg.toString() ?? '');
    final bodyFat = TextEditingController(
      text: entry?.bodyFatPercentage?.toString() ?? '',
    );
    final date = entry?.date ?? DateTime.now();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry == null ? 'Log measurement' : 'Edit measurement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Date: ${date.year}-${date.month}-${date.day}'),
            TextField(
              controller: weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
            ),
            TextField(
              controller: bodyFat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Body fat % (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final weightKg = double.tryParse(weight.text);
    if (weightKg == null || weightKg <= 0) return;
    final fat = double.tryParse(bodyFat.text);
    await ref.read(bodyMetricsDaoProvider).upsert(
          BodyMetricsTableCompanion.insert(
            id: entry?.id ?? _uuid.v4(),
            date: date,
            weightKg: weightKg,
            bodyFatPercentage: Value(fat),
          ),
        );
  }
}

class _BodyWeightChart extends StatelessWidget {
  const _BodyWeightChart({required this.entries});
  final List<BodyMetrics> entries;

  @override
  Widget build(BuildContext context) {
    final ordered = entries.reversed.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 180,
        child: LineChart(LineChartData(
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < ordered.length; i++)
                  FlSpot(i.toDouble(), ordered[i].weightKg),
              ],
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        )),
      ),
    );
  }
}

class _OneRmChart extends StatelessWidget {
  const _OneRmChart({
    required this.points,
    required this.loading,
    required this.unit,
  });
  final List<OneRMSeriesPoint> points;
  final bool loading;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator();
    if (points.isEmpty) {
      return const _ChartEmpty(
          icon: Icons.show_chart, message: 'No completed sets yet.');
    }
    final ordered = points.reversed.toList();
    return SizedBox(
      height: 220,
      child: LineChart(LineChartData(
        minY: 0,
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${UnitFormatters.weight(spot.y, unit)}\n',
                  Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                  children: [
                    TextSpan(
                      text: DateFormatters.full(
                        ordered[spot.x.toInt()].date,
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onInverseSurface,
                          ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < ordered.length; i++)
                FlSpot(i.toDouble(), ordered[i].estimated1RM),
            ],
            isCurved: true,
            dotData: const FlDotData(show: true),
            barWidth: 3,
          ),
        ],
      )),
    );
  }
}

class _VolumeChart extends StatelessWidget {
  const _VolumeChart({
    required this.points,
    required this.loading,
    required this.unit,
  });
  final List<WeeklyVolume> points;
  final bool loading;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator();
    if (points.isEmpty) {
      return const _ChartEmpty(
          icon: Icons.bar_chart, message: 'Complete a workout to see volume.');
    }
    return SizedBox(
      height: 220,
      child: BarChart(BarChartData(
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              '${UnitFormatters.volume(points[group.x].totalVolumeKg, unit)}\n',
              Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
              children: [
                TextSpan(
                  text:
                      'Week of ${DateFormatters.full(points[group.x].weekStart)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                      ),
                ),
              ],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
                x: i, barRods: [BarChartRodData(toY: points[i].totalVolumeKg)]),
        ],
      )),
    );
  }
}

/// Fixed-order categorical palette, stepped for light/dark chart surfaces.
/// Order matters — it's what keeps adjacent bars distinguishable under
/// colour-vision deficiency, so slots are never reassigned or cycled.
const _muscleGroupPaletteLight = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF4A3AA7),
];
const _muscleGroupPaletteDark = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
];
const _muscleGroupOtherColor = Color(0xFF898781);

/// Beyond this many groups, the smallest ones fold into "Other" rather than
/// generating a new hue — an unbounded categorical palette is not readable.
const _maxMuscleGroupSlots = 7;

class _MuscleGroupChart extends StatefulWidget {
  const _MuscleGroupChart({required this.points, required this.loading});
  final List<MuscleGroupVolume> points;
  final bool loading;

  @override
  State<_MuscleGroupChart> createState() => _MuscleGroupChartState();
}

class _MuscleGroupChartState extends State<_MuscleGroupChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final loading = widget.loading;
    if (loading) return const LinearProgressIndicator();
    if (points.isEmpty) {
      return const _ChartEmpty(
        icon: Icons.pie_chart_outline,
        message: 'Complete a workout to see your muscle-group split.',
      );
    }

    final grouped = <MuscleGroupVolume>[];
    if (points.length <= _maxMuscleGroupSlots) {
      grouped.addAll(points);
    } else {
      grouped.addAll(points.take(_maxMuscleGroupSlots));
      final otherTotal = points
          .skip(_maxMuscleGroupSlots)
          .fold<double>(0, (sum, p) => sum + p.totalVolumeKg);
      grouped.add(
        MuscleGroupVolume(
          muscleId: '_other',
          muscleName: 'Other',
          totalVolumeKg: otherTotal,
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? _muscleGroupPaletteDark : _muscleGroupPaletteLight;
    Color colorFor(int index, String muscleId) => muscleId == '_other'
        ? _muscleGroupOtherColor
        : palette[index % palette.length];

    final touchedIndex = _touchedIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mirrors the canvas tooltip as real text — canvas-painted tooltips
        // aren't reachable by screen readers or widget tests, so every value
        // the tooltip shows needs a plain-text home too.
        Text(
          touchedIndex == null
              ? 'Tap or hover a bar for details.'
              : '${grouped[touchedIndex].muscleName}: '
                  '${grouped[touchedIndex].totalVolumeKg.toStringAsFixed(0)} kg',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: BarChart(BarChartData(
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= grouped.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Transform.rotate(
                        angle: -0.5,
                        child: Text(
                          grouped[index].muscleName,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              // handleBuiltInTouches keeps the canvas tooltip (mouse hover and
              // touch tap both drive it, via fl_chart's shared FlTouchEvent
              // pipeline); touchCallback additionally mirrors the touched bar
              // into the plain-text readout above.
              touchCallback: (event, response) {
                final spot = response?.spot;
                setState(() {
                  _touchedIndex =
                      event.isInterestedForInteractions && spot != null
                          ? spot.touchedBarGroupIndex
                          : null;
                });
              },
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final muscle = grouped[group.x];
                  return BarTooltipItem(
                    '${muscle.muscleName}\n',
                    Theme.of(context).textTheme.labelMedium!.copyWith(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                    children: [
                      TextSpan(
                        text: '${muscle.totalVolumeKg.toStringAsFixed(0)} kg',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                ),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < grouped.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: grouped[i].totalVolumeKg,
                      color: colorFor(i, grouped[i].muscleId),
                      width: 22,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
          )),
        ),
      ],
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: icon,
        title: 'No data yet',
        message: message,
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}
