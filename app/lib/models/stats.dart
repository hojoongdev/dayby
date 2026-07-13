/// One day, as the caregiver lived it. The server buckets by their midnight, not UTC's.
class DayStat {
  const DayStat({
    required this.date,
    this.feeds = 0,
    this.feedMl = 0,
    this.avgFeedGapMin,
    this.diapers = const {},
    this.napMin = 0,
    this.nightSleepMin = 0,
  });

  final String date;
  final int feeds;
  final double feedMl;

  /// What actually changes as a baby grows is not how much they take but how long they
  /// go between takes. Null on a day with fewer than two feeds — there is no gap.
  final int? avgFeedGapMin;

  final Map<String, int> diapers;
  final int napMin;
  final int nightSleepMin;

  int get diaperCount => diapers.values.fold(0, (a, b) => a + b);
  int get sleepMin => napMin + nightSleepMin;

  factory DayStat.fromJson(Map<String, dynamic> json) => DayStat(
        date: json['date'] as String,
        feeds: json['feeds'] as int? ?? 0,
        feedMl: (json['feed_ml'] as num?)?.toDouble() ?? 0,
        avgFeedGapMin: json['avg_feed_gap_min'] as int?,
        diapers: (json['diapers'] as Map?)?.map(
              (k, v) => MapEntry(k as String, v as int),
            ) ??
            const {},
        napMin: json['nap_min'] as int? ?? 0,
        nightSleepMin: json['night_sleep_min'] as int? ?? 0,
      );
}

class GrowthPoint {
  const GrowthPoint({required this.time, this.weightKg, this.heightCm});

  final DateTime time;
  final double? weightKg;
  final double? heightCm;

  factory GrowthPoint.fromJson(Map<String, dynamic> json) => GrowthPoint(
        time: DateTime.parse(json['time'] as String),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        heightCm: (json['height_cm'] as num?)?.toDouble(),
      );
}

/// One block on the 24-hour view. A sleep is a long block; a feed or a nappy is a mark.
/// Laid one day above another, the shape of a baby's day is the thing you can watch change.
class RhythmBlock {
  const RhythmBlock({
    required this.date,
    required this.type,
    required this.startMin,
    this.minutes = 0,
  });

  final String date;
  final String type;

  /// Minutes past the caregiver's own midnight, so the days line up under each other.
  final int startMin;
  final int minutes;

  factory RhythmBlock.fromJson(Map<String, dynamic> json) => RhythmBlock(
        date: json['date'] as String,
        type: json['type'] as String,
        startMin: json['start_min'] as int,
        minutes: json['minutes'] as int? ?? 0,
      );
}

class Stats {
  const Stats({this.days = const [], this.growth = const [], this.rhythm = const []});

  final List<DayStat> days;
  final List<GrowthPoint> growth;
  final List<RhythmBlock> rhythm;

  bool get isEmpty => days.isEmpty && growth.isEmpty;

  factory Stats.fromJson(Map<String, dynamic> json) => Stats(
        days: (json['days'] as List? ?? const [])
            .map((e) => DayStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        growth: (json['growth'] as List? ?? const [])
            .map((e) => GrowthPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        rhythm: (json['rhythm'] as List? ?? const [])
            .map((e) => RhythmBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
