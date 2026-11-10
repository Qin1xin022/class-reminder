import 'package:flutter_test/flutter_test.dart';
import 'package:class_reminder/services/timetable_parser.dart';

final gdut = <(int, int)>[
  (510, 555), (560, 605), (625, 670), (675, 720),
  (830, 875), (880, 925), (930, 975), (990, 1035), (1040, 1085),
  (1110, 1155), (1160, 1205), (1210, 1255),
];

void main() {
  group('parseCellText', () {
    test('多行格子：课程/老师/周次/地点', () {
      final p = parseCellText('高等数学\n张老师\n1-16周\n教404');
      expect(p.name, '高等数学');
      expect(p.teacher, '张老师');
      expect(p.location, '教404');
      expect(p.weekStart, 1);
      expect(p.weekEnd, 16);
    });

    test('单行带节次和周次', () {
      final p = parseCellText('大学英语 第3-4节 2-17周 A栋201');
      expect(p.name, contains('大学英语'));
      expect(p.startPeriod, 3);
      expect(p.endPeriod, 4);
      expect(p.weekStart, 2);
      expect(p.weekEnd, 17);
      expect(p.location, contains('201'));
    });

    test('单双周', () {
      final p = parseCellText('体育 单周 3-15周 操场');
      expect(p.weekStart, 3);
      expect(p.weekEnd, 15);
      final q = parseCellText('体育 双周 3-16周 操场');
      expect(q.weekStart, 4);
      expect(q.weekEnd, 16);
    });

    test('直接给时间', () {
      final p = parseCellText('心理健康 08:30-10:10');
      expect(p.startMin, 510);
      expect(p.endMin, 610);
    });
  });

  group('parseGrid', () {
    test('典型教务 xlsx 网格', () {
      final grid = [
        ['节次\\星期', '周一', '周二', '周三', '周四', '周五'],
        ['第1-2节', '高等数学\n1-16周\n教404', '大学英语\n2-17周\n文B302', '', '数据结构\n1-16周\n机房501', ''],
        ['第3-4节', '物理\n1-16周\n实A101', '', '大学英语\n2-17周\n文B302', '', '体育\n3-16周\n操场'],
        ['第5-6节', '', '心理健康\n1-16周\n教201', '', '高等数学\n1-16周\n教404', ''],
      ];
      final list = parseGrid(grid, gdut);
      expect(list.length, 8);
      final math = list.firstWhere((c) => c.name == '高等数学' && c.weekday == 1);
      expect(math.startMin, 510);
      expect(math.endMin, 605);
      expect(math.weekStart, 1);
      expect(math.weekEnd, 16);
      final pe = list.firstWhere((c) => c.name == '体育');
      expect(pe.weekday, 5);
      expect(pe.weekStart, 3);
      expect(pe.location, contains('操场'));
    });

    test('节次列不带「第」字', () {
      final grid = [
        ['时间', '星期一', '星期二'],
        ['1,2节', 'Java程序设计\n1-16周\n机房301', ''],
        ['3,4节', '', '线性代数\n1-16周\n教301'],
      ];
      final list = parseGrid(grid, gdut);
      expect(list.length, 2);
      // "1,2节" 解析出节次 1-2
      expect(list.first.startMin, 510);
    });
  });

  group('parseLooseText', () {
    test('每行自带星期', () {
      final text = '''
周一 第1-2节 1-16周 高等数学 教404
周五 第3-4节 2-17周 大学英语 文B302
''';
      final list = parseLooseText(text, gdut);
      expect(list.length, 2);
      expect(list[0].weekday, 1);
      expect(list[0].startMin, 510);
      expect(list[1].weekday, 5);
      expect(list[1].location, contains('B302'));
    });

    test('制表符伪表格', () {
      final text = ['\t周一\t周二', '1-2节\t大学物理\t高数', '3-4节\t\t英语'].join('\n');
      final list = parseLooseText(text, gdut);
      // ignore: avoid_print
      for (final c in list) {
        // ignore: avoid_print
        print('DBG wd=${c.weekday} sp=${c.startMin} ep=${c.endMin} name=${c.name} loc=${c.location} t=${c.teacher}');
      }
      expect(list.length, 3);
      expect(list.any((c) => c.name.contains('大学物理') && c.weekday == 1), true);
      expect(list.any((c) => c.name.contains('英语') && c.weekday == 2), true);
    });
  });
}
