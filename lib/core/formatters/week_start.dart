/// The day a week begins on, as chosen in Settings.
///
/// Three days, not seven: between them Saturday, Sunday and Monday are the
/// first day of the week practically everywhere, and a control with seven
/// choices would bury them.
///
/// Everything that groups by week reads this one value: the weekly totals
/// and streaks (bucketed in SQL), the dashboard's week card and day strip,
/// the history calendar's columns and the weekday chart's order. Nothing is
/// stored by week, so changing it only regroups what is shown.
enum WeekStart {
  saturday(DateTime.saturday),
  sunday(DateTime.sunday),
  monday(DateTime.monday);

  const WeekStart(this.weekday);

  /// This day as a [DateTime.weekday] value (Monday = 1 … Sunday = 7).
  final int weekday;

  /// How many days into the week [weekday] falls: 0 for the first day,
  /// 6 for the last. [weekday] is a [DateTime.weekday] value.
  int indexOf(int weekday) => (weekday - this.weekday) % DateTime.daysPerWeek;

  /// The seven [DateTime.weekday] values in the order this week runs.
  List<int> get weekdays => <int>[
        for (int i = 0; i < DateTime.daysPerWeek; i++)
          (weekday - 1 + i) % DateTime.daysPerWeek + 1,
      ];

  /// The week's *last* day in SQLite's numbering (Sunday = 0 … Saturday = 6).
  ///
  /// SQLite has no "start of week". It has `'weekday N'`, which moves a date
  /// forward to the next day N (or leaves it, if it already is one). Moving
  /// forward to the week's last day and stepping back six lands on its
  /// first: `date(x, 'weekday N', '-6 days')`.
  int get sqliteLastWeekday =>
      (weekday + DateTime.daysPerWeek - 1) % DateTime.daysPerWeek;
}
