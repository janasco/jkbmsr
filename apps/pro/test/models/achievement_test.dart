import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/models/achievement.dart';

void main() {
  test('an earned date is read as UTC, whichever shape the server sends', () {
    // D1 stores `YYYY-MM-DD HH:MM:SS` with no marker; Dart would read that as local
    // time and a device clock could make a milestone look earned a day early or late.
    final compact = Achievement.fromJson({
      'key': 'first_pack',
      'title': 'First pack',
      'detail': 'Contribute your first pack.',
      'points': 50,
      'earnedAt': '2026-11-24 03:10:00',
    });
    expect(compact.earned, isTrue);
    expect(compact.earnedAt!.isUtc, isTrue);
    expect(compact.earnedAt, DateTime.utc(2026, 11, 24, 3, 10));

    final iso = Achievement.fromJson({
      'key': 'first_pack',
      'title': 'First pack',
      'detail': 'Contribute your first pack.',
      'points': 50,
      'earnedAt': '2026-11-24T03:10:00Z',
    });
    expect(iso.earnedAt, DateTime.utc(2026, 11, 24, 3, 10));
  });

  test('no date means not earned, never a default date', () {
    final locked = Achievement.fromJson({
      'key': 'ten_packs',
      'title': 'Ten packs',
      'detail': 'Ten accepted packs.',
      'points': 100,
      'earnedAt': null,
    });
    expect(locked.earned, isFalse);
    expect(locked.earnedAt, isNull);
  });

  test('the summary counts only what was earned and sums its points', () {
    final summary = AchievementSummary.fromJson({
      'achievements': [
        {'key': 'a', 'title': 'A', 'detail': 'a', 'points': 50, 'earnedAt': '2026-11-24 03:10:00'},
        {'key': 'b', 'title': 'B', 'detail': 'b', 'points': 25, 'earnedAt': '2026-11-24 03:10:00'},
        {'key': 'c', 'title': 'C', 'detail': 'c', 'points': 150, 'earnedAt': null},
      ],
      'pointsEarned': 75,
    });
    expect(summary.achievements, hasLength(3));
    expect(summary.earnedCount, 2);
    expect(summary.pointsEarned, 75);
  });
}
