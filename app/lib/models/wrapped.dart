/// A whole babyhood, counted: the numbers MongoDB aggregated, and the story the
/// model wrote from them.
class Wrapped {
  const Wrapped({required this.stats, this.story = '', this.lang = 'en'});

  final WrappedStats stats;
  final String story;
  final String lang;

  factory Wrapped.fromJson(Map<String, dynamic> json) => Wrapped(
        stats: WrappedStats.fromJson(json['stats'] as Map<String, dynamic>),
        story: json['story'] as String? ?? '',
        lang: json['lang'] as String? ?? 'en',
      );
}

class WrappedStats {
  const WrappedStats({
    this.daysTracked = 0,
    this.totalEvents = 0,
    this.feedings = 0,
    this.totalFeedMl = 0,
    this.nightFeeds = 0,
    this.diapers = 0,
    this.sleeps = 0,
    this.busiestDay,
    this.busiestDayEvents = 0,
    this.topTypes = const {},
    this.spend = const [],
    this.milestones = const [],
    this.firstWeightKg,
    this.lastWeightKg,
    this.firstHeightCm,
    this.lastHeightCm,
  });

  final int daysTracked;
  final int totalEvents;
  final int feedings;
  final double totalFeedMl;
  final int nightFeeds;
  final int diapers;
  final int sleeps;
  final String? busiestDay;
  final int busiestDayEvents;
  final Map<String, int> topTypes;
  final List<Spend> spend;
  final List<Milestone> milestones;
  final double? firstWeightKg;
  final double? lastWeightKg;
  final double? firstHeightCm;
  final double? lastHeightCm;

  bool get isEmpty => totalEvents == 0;

  bool get hasGrowth => firstWeightKg != null || firstHeightCm != null;

  static double? _d(dynamic v) => (v as num?)?.toDouble();

  factory WrappedStats.fromJson(Map<String, dynamic> json) => WrappedStats(
        daysTracked: json['days_tracked'] as int? ?? 0,
        totalEvents: json['total_events'] as int? ?? 0,
        feedings: json['feedings'] as int? ?? 0,
        totalFeedMl: _d(json['total_feed_ml']) ?? 0,
        nightFeeds: json['night_feeds'] as int? ?? 0,
        diapers: json['diapers'] as int? ?? 0,
        sleeps: json['sleeps'] as int? ?? 0,
        busiestDay: json['busiest_day'] as String?,
        busiestDayEvents: json['busiest_day_events'] as int? ?? 0,
        topTypes: (json['top_types'] as Map?)?.cast<String, int>() ?? const {},
        spend: (json['spend'] as List? ?? const [])
            .map((s) => Spend.fromJson(s as Map<String, dynamic>))
            .toList(),
        milestones: (json['milestones'] as List? ?? const [])
            .map((m) => Milestone.fromJson(m as Map<String, dynamic>))
            .toList(),
        firstWeightKg: _d(json['first_weight_kg']),
        lastWeightKg: _d(json['last_weight_kg']),
        firstHeightCm: _d(json['first_height_cm']),
        lastHeightCm: _d(json['last_height_cm']),
      );
}

class Spend {
  const Spend({required this.currency, required this.total, required this.count});

  final String currency;
  final double total;
  final int count;

  factory Spend.fromJson(Map<String, dynamic> json) => Spend(
        currency: json['currency'] as String,
        total: (json['total'] as num).toDouble(),
        count: json['count'] as int,
      );
}

class Milestone {
  const Milestone({required this.time, this.text});

  final DateTime time;
  final String? text;

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
        time: DateTime.parse(json['time'] as String),
        text: json['text'] as String?,
      );
}
