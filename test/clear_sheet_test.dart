import 'package:flutter_test/flutter_test.dart';
import 'package:class_reminder/models.dart';
import 'package:class_reminder/state/app_state.dart';

Course course(String name,
        {int wd = 1, int ws = 1, int we = 16, int id = 1}) =>
    Course(
      id: id,
      name: name,
      weekday: wd,
      startMin: 510,
      endMin: 555,
      weekStart: ws,
      weekEnd: we,
    );

void main() {
  test('清空课表：按周次交集取要删的课', () {
    final s = AppState();
    s.courses = [
      course('长期课', ws: 1, we: 16),
      course('前半学期', ws: 1, we: 8),
      course('后半学期', ws: 9, we: 16),
      course('单周课', ws: 11, we: 11),
    ];
    // 第 11 周：长期、后半、单周都会上
    expect(s.coursesInWeeks(11, 11).length, 3);
    // 第 1 周：长期、前半
    expect(s.coursesInWeeks(1, 1).length, 2);
    // 第 17 周起没课
    expect(s.coursesInWeeks(17, 20), isEmpty);
    // 整个学期 = 全部
    expect(s.courses, hasLength(4));
  });

  test('清空课表：本月覆盖的周次范围', () {
    final s = AppState();
    s.termStart = '2026-09-01';
    final (a, b) = s.weeksOfMonth(DateTime(2026, 11, 11));
    // 11/1 在 9/1 起算的第 9 周，11/30 在第 13 周
    expect(a, s.weekOf(DateTime(2026, 11, 1)));
    expect(b, s.weekOf(DateTime(2026, 11, 30)));
    expect(a, lessThanOrEqualTo(b));
  });

  test('清空课表：跨月的月份不会颠倒顺序', () {
    final s = AppState();
    s.termStart = '2026-09-01';
    for (var m = 1; m <= 12; m++) {
      final (a, b) = s.weeksOfMonth(DateTime(2026, m, 15));
      expect(a, lessThanOrEqualTo(b), reason: '2026-$m 月');
    }
  });
}
