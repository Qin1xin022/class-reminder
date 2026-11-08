import 'package:flutter_test/flutter_test.dart';
import 'package:class_reminder/utils/extract.dart';

void main() {
  test('结构化提取：时间/地点/谁/开始/截止', () {
    const text = '''
各位同学：
2026年11月10日（周二）18:30 在教工(东)-601 举行英语演讲比赛初赛，请提前10分钟到场签到。
报名截止时间为11月9日22:00之前，最晚不晚于当天，逾期不接受报名。
报名表填好后发给李明老师，有问题联系负责人：王芳同学。
腾讯会议号：123456789，线上的同学通过会议参加。
''';
    final r = extractNotice(text);
    print('---- keyPoints ----');
    for (final p in r.keyPoints) {
      print(p);
    }
    print('---- links: ${r.links}');
    print('---- deadlines: ${r.deadlines}');
    expect(r.keyPoints, isNotEmpty);
    expect(r.keyPoints.any((p) => p.contains('2026年11月10日')), isTrue,
        reason: '开始时间要完整');
    expect(r.keyPoints.any((p) => p.contains('教工(东)-601') || p.contains('教工（东）-601')), isTrue,
        reason: '地点要完整');
    expect(r.keyPoints.any((p) => p.contains('李明老师')), isTrue, reason: '人名要完整');
  });
}
