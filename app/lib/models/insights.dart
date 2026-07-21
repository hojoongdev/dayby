/// When the baby's own rhythm suggests the next one is due. An estimate, not a rule.
class Prediction {
  const Prediction({required this.type, required this.at, required this.basis});

  final String type;
  final DateTime at;
  final String basis;

  factory Prediction.fromJson(Map<String, dynamic> json) => Prediction(
        type: json['type'] as String,
        at: DateTime.parse(json['at'] as String),
        basis: json['basis'] as String,
      );
}

/// Looking forward (predictions) and back (the week's trend observations).
class Insights {
  const Insights({
    this.predictions = const [],
    this.observations = const [],
    this.lang = 'en',
  });

  final List<Prediction> predictions;
  final List<String> observations;
  final String lang;

  bool get isEmpty => predictions.isEmpty && observations.isEmpty;

  factory Insights.fromJson(Map<String, dynamic> json) => Insights(
        predictions: (json['predictions'] as List? ?? const [])
            .map((p) => Prediction.fromJson(p as Map<String, dynamic>))
            .toList(),
        observations:
            (json['observations'] as List? ?? const []).cast<String>(),
        lang: json['lang'] as String? ?? 'en',
      );
}
