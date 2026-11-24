/// One milestone in the contributor game.
///
/// Points are awarded by the server when a linked capture completes the
/// condition, and they belong to the ACCOUNT: the same list is shown whichever
/// gateway is opened, and a gateway only ever appears as the pack that earned it.
class Achievement {
  const Achievement({
    required this.key,
    required this.title,
    required this.detail,
    required this.points,
    required this.earnedAt,
  });

  final String key;
  final String title;
  final String detail;
  final int points;

  /// Null means not yet earned. The date is the server's, not the phone's, so a
  /// wrong device clock cannot make a milestone look earned.
  final DateTime? earnedAt;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    final raw = json['earnedAt'] as String?;
    return Achievement(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      // D1 writes `YYYY-MM-DD HH:MM:SS` with no marker, and Dart reads that as
      // local time. A value that already carries `T` is left alone.
      earnedAt: raw == null
          ? null
          : DateTime.tryParse(raw.contains('T') ? raw : '${raw.replaceFirst(' ', 'T')}Z'),
    );
  }

  bool get earned => earnedAt != null;
}

class AchievementSummary {
  const AchievementSummary({
    required this.achievements,
    required this.pointsEarned,
  });

  final List<Achievement> achievements;
  final int pointsEarned;

  int get earnedCount => achievements.where((a) => a.earned).length;

  factory AchievementSummary.fromJson(Map<String, dynamic> json) {
    final list = (json['achievements'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Achievement.fromJson)
        .toList();
    return AchievementSummary(
      achievements: list,
      pointsEarned: (json['pointsEarned'] as num?)?.toInt() ?? 0,
    );
  }
}
