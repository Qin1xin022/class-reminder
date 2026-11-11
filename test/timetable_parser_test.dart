import 'package:flutter_test/flutter_test.dart';
import 'package:class_reminder/models.dart';
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

    friendFormatTests();
  });
}

/// 模拟「今日校园」式课表截图（列头带日期、"今天"列、行标签是裸数字、
/// 教室是 @xxx 格式、课程名被拆行）
List<OcrTextLine> mockFriendTimetable() {
  const colX = [66.0, 122.0, 180.0, 240.0, 300.0, 360.0, 418.0];
  final lines = <OcrTextLine>[
    const OcrTextLine('节 数', 8, 195, 30, 221),
  ];
  const heads = ['周一', '周二', '今天', '周四', '周五', '周六', '周日'];
  const dates = ['11/09', '11/10', '11/11', '11/12', '11/13', '11/14', '11/15'];
  for (var i = 0; i < 7; i++) {
    final cx = colX[i];
    lines.add(OcrTextLine(heads[i], cx - 16, 192, cx + 16, 218));
    lines.add(OcrTextLine(dates[i], cx - 16, 220, cx + 16, 246));
  }
  for (var i = 0; i < 12; i++) {
    final top = 232.0 + i * 56;
    lines.add(OcrTextLine('${i + 1}', 10, top, 30, top + 26));
  }
  void cell(int col, int period, List<String> textLines) {
    final cx = colX[col - 1];
    final top = 232.0 + (period - 1) * 56 + 4;
    for (var j = 0; j < textLines.length; j++) {
      lines.add(OcrTextLine(textLines[j], cx - 30, top + j * 30, cx + 30, top + j * 30 + 26));
    }
  }

  cell(1, 1, ['大学生', '心理健康', '教育@4-10']);
  cell(2, 1, ['计算机', '系统导', '论@10-309']);
  cell(3, 1, ['大学英语', 'III-1@10-5-03']);
  cell(4, 1, ['高等数', '学(II)(III)', '-1@3-506']);
  cell(1, 3, ['C 语言', '程序设计', '基础@3-3']);
  cell(2, 3, ['大学英语', 'III-1@3-506']);
  cell(4, 3, ['C 语言', '程序设计', '基础@3-40']);
  cell(5, 3, ['数字电', '路与数', '字逻辑@6-50']);
  cell(1, 5, ['计算机', '系统导', '论@7-406']);
  cell(2, 5, ['数字电', '路与数', '字逻辑@1-50']);
  cell(4, 5, ['C 语言', '程序设计', '基础@2-30']);
  cell(5, 5, ['计算机', '系统导', '论@7-406']);
  cell(1, 7, ['数字电', '路与数', '字逻辑@6-50']);
  cell(2, 7, ['排球俱', '乐部-1', '@排球场']);
  cell(4, 7, ['形势与', '政策-1', '@3-202']);
  cell(1, 9, ['思想道', '德与法', '治@5-302']);
  cell(2, 9, ['大学生', '职业发展', '与就业指导']);
  cell(3, 9, ['排球第', '一课堂', '@一啪']);
  cell(4, 9, ['礼仪培', '训@4-201']);
  return lines;
}

void friendFormatTests() {
  test('课程名@教室：名字被拆行也能拼回，@ 后面是地点', () {
    final p = parseCellText('大学生\n心理健康\n教育@4-10');
    expect(p.name, '大学生心理健康教育');
    expect(p.location, '4-10');
    expect(p.weekStart, 1);
    expect(p.weekEnd, 16); // 没写周次时默认整学期
  });

  test('裸数字行标签 + 「今天」列头 + 日期列头的课表截图', () {
    final lines = mockFriendTimetable();
    final anchors = headerAnchors(lines);
    // 7 列全部认出来，「今天」列按日期 11/11 推算出星期
    expect(anchors.length, 7);
    final wed = DateTime(DateTime.now().year, 11, 11).weekday;
    expect(anchors[3], isNotNull); // 周三列存在

    final (list, _) = gridFromOcrLines(lines, anchors, gdut);
    expect(list.length, 19);

    Course find(String name, int wd) =>
        list.firstWhere((c) => c.name == name && c.weekday == wd);

    final pe = find('大学生心理健康教育', 1);
    expect(pe.startMin, 510);
    expect(pe.endMin, 605); // 第1-2节
    expect(pe.location, '4-10');

    final en = find('大学英语III-1', wed); // 「今天」列 = 周三
    expect(en.startMin, 510);
    expect(en.location, '10-5-03');

    final c1 = find('C 语言程序设计基础', 1);
    expect(c1.startMin, 625); // 第3-4节
    expect(c1.endMin, 720);
    expect(c1.location, '3-3');

    final cs = list.where((c) => c.name == 'C 语言程序设计基础' && c.weekday == 4).toList();
    expect(cs.length, 2);
    expect(cs[0].startMin, 625); // 第3-4节
    expect(cs[0].endMin, 720);
    expect(cs[0].location, '3-40');
    expect(cs[1].startMin, 830); // 第5-6节
    expect(cs[1].endMin, 925);
    expect(cs[1].location, '2-30');
  });

  test('日期夹在文字里不会误判成列头', () {
    expect(weekdayFromHeaderToken('礼仪培训@4-201'), isNull);
    expect(weekdayFromHeaderToken('教404'), isNull);
    expect(weekdayFromHeaderToken('周一'), 1);
    expect(weekdayFromHeaderToken('11/09'), DateTime(DateTime.now().year, 11, 9).weekday);
    expect(weekdayFromHeaderToken('今天'), DateTime.now().weekday);
  });

  friend2FormatTests();
}

/// 模拟第二位朋友的课表截图（WakeUp 风格）：
/// 行标签是「节次数字 + 起止时间」竖排、教室号被换行拆开（@南霄3 / 27）、
/// 格子紧贴着排（无空隙）、跨 2~3 节的大格子、还有一个「+」按钮。
List<OcrTextLine> mockFriend2Timetable() {
  const colX = [66.0, 122.0, 180.0, 240.0, 300.0, 360.0, 418.0];
  final lines = <OcrTextLine>[
    const OcrTextLine('第9周', 160, 78, 230, 106), // 顶部标题，应被忽略
  ];
  const heads = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  const dates = ['11/09', '11/10', '11/11', '11/12', '11/13', '11/14', '11/15'];
  for (var i = 0; i < 7; i++) {
    final cx = colX[i];
    lines.add(OcrTextLine(heads[i], cx - 16, 118, cx + 16, 144));
    lines.add(OcrTextLine(dates[i], cx - 16, 146, cx + 16, 172));
  }
  // 每行行高不一样（1-6 节高、7-8 节矮、9-10 节最高），时间是 45 分钟/节
  const times = [
    ['08:00', '08:45'], ['08:46', '09:30'], ['09:35', '10:20'],
    ['10:31', '11:15'], ['11:30', '12:15'], ['12:16', '13:00'],
    ['13:15', '14:00'], ['14:01', '14:45'], ['14:46', '15:30'],
    ['15:45', '16:30'], ['16:31', '17:15'], ['17:16', '18:00'],
    ['18:15', '19:00'],
  ];
  const rowH = [76.0, 76.0, 76.0, 76.0, 76.0, 76.0, 62.0, 62.0, 88.0, 88.0, 62.0, 62.0, 62.0];
  final rowTop = <double>[232];
  for (var i = 1; i < rowH.length; i++) {
    rowTop.add(rowTop.last + rowH[i - 1]);
  }
  double rowTopOf(int p) => rowTop[p - 1];
  for (var i = 0; i < 13; i++) {
    final top = rowTop[i];
    lines.add(OcrTextLine('${i + 1}', 10, top, 30, top + 26));
    lines.add(OcrTextLine(times[i][0], 2, top + 28, 48, top + 50));
    lines.add(OcrTextLine(times[i][1], 2, top + 54, 48, top + 76));
  }
  // 格子紧贴：文字行间距 28，块与块之间无空隙
  void cell(int col, int startP, List<String> textLines) {
    final cx = colX[col - 1];
    final top = rowTopOf(startP) + 4;
    for (var j = 0; j < textLines.length; j++) {
      lines.add(OcrTextLine(textLines[j], cx - 30, top + j * 28, cx + 30, top + j * 28 + 24));
    }
  }

  cell(1, 3, ['大学英语1', '@行知21', '9']);
  cell(1, 9, ['体育1']);
  cell(2, 1, ['军事理论', '@南霄3', '27']);
  cell(2, 3, ['思想道', '德与法', '治@南教2', '20']); // 跨 3 节的大格子
  cell(2, 7, ['高等', '数学C', '@南高2', '41']);
  cell(4, 1, ['计算', '思维', '@燕宾5', '05']);
  cell(4, 3, ['国家', '安全', '教育', '@临风3', '20']);
  cell(4, 7, ['管理', '学', '@南商1', '02']);
  cell(4, 9, ['中国', '画鉴', '赏与', '实践', '@楼观1', '02']);
  cell(5, 3, ['高等', '数学C', '@南高2', '41']);
  cell(5, 5, ['大学', '英语1', '@南语5', '05']);
  cell(5, 9, ['政治', '经济', '学', '@馆实31', '7']);
  cell(6, 8, ['+']); // 「添加课程」按钮，不应被当成课程
  return lines;
}

void friend2FormatTests() {
  test('紧贴格子 + 换行拆开的门牌号 + 「+」按钮的课表截图', () {
    final lines = mockFriend2Timetable();
    final anchors = headerAnchors(lines);
    expect(anchors.length, 7);

    final (list, detected) = gridFromOcrLines(lines, anchors, gdut);
    // 12 门课，「+」不算
    expect(list.length, 12);

    Course find(String name, int wd) =>
        list.firstWhere((c) => c.name == name && c.weekday == wd);

    // 教室号被换行拆开也能拼回去
    final mil = find('军事理论', 2);
    expect(mil.startMin, 510); // 第1-2节
    expect(mil.endMin, 605);
    expect(mil.location, '南霄327');

    // 名字被拆行 + @ 在行中间
    final ide = find('思想道德与法治', 2);
    expect(ide.location, '南教220');
    expect(ide.startMin, 625); // 第3节起
    expect(ide.endMin, 720); // 文字只盖到第4节行标签（3 节连堂识别为 2 节，核对页可改）

    final calc = find('计算思维', 4);
    expect(calc.location, '燕宾505');
    expect(calc.startMin, 510);

    final pe = find('体育1', 1); // 没有教室
    expect(pe.location, '');
    expect(pe.startMin, 1040); // 第9-10节

    final engFri = find('大学英语1', 5);
    expect(engFri.location, '南语505');
    expect(engFri.startMin, 830); // 第5-6节
    expect(engFri.endMin, 925);

    final pol = find('政治经济学', 5);
    expect(pol.location, '馆实317');
    expect(pol.startMin, 1040);

    expect(find('管理学', 4).location, '南商102');
    expect(find('中国画鉴赏与实践', 4).location, '楼观102');
    expect(find('国家安全教育', 4).location, '临风320');
    expect(find('高等数学C', 2).location, '南高241');
    expect(find('高等数学C', 5).startMin, 625);
    expect(find('大学英语1', 1).location, '行知219');

    // 没把「+」或标题当成课程
    expect(list.where((c) => c.name == '+'), isEmpty);
    expect(list.any((c) => c.weekday == 3), isFalse);
    expect(list.any((c) => c.weekday == 6), isFalse);

    // 从行标签识别出了作息时间（13 节，45 分钟/节）
    expect(detected, isNotNull);
    expect(detected!.length, 13);
    expect(detected[0], (480, 525)); // 08:00-08:45
    expect(detected[1], (526, 570)); // 08:46-09:30
    expect(detected[8], (886, 930)); // 14:46-15:30
    expect(detected[12], (1095, 1140)); // 18:15-19:00
  });
}
