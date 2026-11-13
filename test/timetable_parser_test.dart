import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:class_reminder/models.dart';
import 'package:class_reminder/services/timetable_parser.dart';
import 'package:class_reminder/services/timetable_file_import.dart';

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

  elementLevelTests();
  wakeUpFormatTests();
  queryAppFormatTests();
}

/// 模拟「课表查询」App 截图（第三位朋友，21 门课）的真实布局：
/// 蓝色标题栏（课表查询/第10周（本周）/状态栏）在网格上方；
/// 列头周X+日期、「今天」列；格子彩色紧贴、文字白色居中、行距 19.5、
/// 行高 55.4；周五列有 2 门课、周六周日全空；周三列 9-10 节有
/// 排球第一课堂@一啪 + 太极拳（第一周）两个叠着的格子。
List<OcrTextLine> mockQueryAppTimetable() {
  double colX(int wd) => 73.5 + (wd - 1) * 57.5;
  const lineH = 19.5, rowPitch = 55.4;
  double rowTop(int p) => 218.3 + (p - 1) * rowPitch;
  final lines = <OcrTextLine>[];

  OcrTextLine el(String t, double cx, double top, {double? w, double h = lineH}) {
    w ??= t.length * 11.3;
    return OcrTextLine(t, cx - w / 2, top, cx + w / 2, top + h);
  }

  // 蓝色区域（网格上方）：状态栏、标题、周次选择器
  lines.add(const OcrTextLine('0:06', 20, 12, 52, 28));
  lines.add(const OcrTextLine('课表查询', 25, 85, 145, 112));
  lines.add(const OcrTextLine('第10周（本周）', 12, 150, 160, 185));
  // 列头：节数 + 周X/今天 + 日期
  const weekNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  lines.add(const OcrTextLine('节数', 12, 196, 38, 240));
  for (var wd = 1; wd <= 7; wd++) {
    lines.add(el(wd == 3 ? '今天' : weekNames[wd - 1], colX(wd), 195, w: 34));
    lines.add(el('11/${8 + wd}', colX(wd), 222, w: 34));
  }
  // 行标签 1~12（裸数字）
  for (var p = 1; p <= 12; p++) {
    lines.add(OcrTextLine('$p', 8, rowTop(p) + 9, 30, rowTop(p) + 28.5));
  }
  // 格子：文字行距 19.5，从格子顶部 +21 开始
  void cell(int wd, int startP, List<String> textLines, {double topShift = 21}) {
    final cx = colX(wd);
    final top = rowTop(startP) + topShift;
    for (var j = 0; j < textLines.length; j++) {
      lines.add(el(textLines[j], cx, top + j * lineH));
    }
  }

  // 周一 5 门
  cell(1, 1, ['大学生心', '理健康教', '育@4-10']);
  cell(1, 3, ['C 语言', '程序设', '计基础', '@10-3']);
  cell(1, 5, ['计算机', '系统导', '论@7-', '406']);
  cell(1, 7, ['数字电', '路与数', '字逻辑', '@6-50']);
  cell(1, 9, ['思想道', '德与法', '治@5-', '302']);
  // 周二 5 门
  cell(2, 1, ['计算机', '系统导', '论@10', '-309']);
  cell(2, 3, ['大学英语', 'III-1@3-', '506']);
  cell(2, 5, ['数字电', '路与数', '字逻辑', '@1-50']);
  cell(2, 7, ['排球俱', '乐部-1', '@排球', '场']);
  cell(2, 9, ['大学生', '职业发', '展与就', '业指导']);
  // 周三（今天）4 门：太极拳叠在排球第一课堂下方（第 10 节内）
  cell(3, 1, ['大学英', '语III-1', '@10-5', '03']);
  cell(3, 3, ['高等数', '学(1)(1', 'II)-1@3-', '507']);
  cell(3, 9, ['排球第', '一课堂', '@一啪']);
  cell(3, 10, ['太极拳', '第一周'], topShift: 30);
  // 周四 5 门
  cell(4, 1, ['高等数', '学(1)(1', 'II)-1@3-', '506']);
  cell(4, 3, ['C 语言', '程序设', '计基础', '@3-40']);
  cell(4, 5, ['C 语言', '程序设', '计基础', '@2-30']);
  cell(4, 7, ['形势与', '政策-1', '@3-20', '2']);
  cell(4, 9, ['礼仪培', '训@4-', '201']);
  // 周五 2 门；周六周日没课
  cell(5, 3, ['数字电', '路与数', '字逻辑', '@6-50']);
  cell(5, 5, ['计算机', '系统导', '论@7-', '406']);
  return lines;
}

void queryAppFormatTests() {
  test('课表查询 App 截图：21 门课全认出（含标题栏干扰与叠放格子）', () {
    final lines = mockQueryAppTimetable();
    final anchors = headerAnchors(lines);
    expect(anchors.length, 7);
    final (list, _) = gridFromOcrLines(lines, anchors, gdut);
    expect(list.length, 21, reason: '21 门课一门不少，标题栏也不许造出假课');

    Course find(String name, int wd) =>
        list.firstWhere((c) => c.name == name && c.weekday == wd);

    // 周一 5 门
    final psych = find('大学生心理健康教育', 1);
    expect(psych.location, '4-10');
    expect(psych.startMin, 510);
    expect(psych.endMin, 605);
    final c10 = find('C 语言程序设计基础', 1);
    expect(c10.location, '10-3');
    expect(c10.startMin, 625);
    expect(c10.endMin, 720);
    expect(find('计算机系统导论', 1).location, '7-406');
    expect(find('数字电路与数字逻辑', 1).startMin, 930);
    final moral = find('思想道德与法治', 1);
    expect(moral.location, '5-302');
    expect(moral.startMin, 1040); // 从第 9 节起
    expect(moral.endMin, 1155); // 文字只推到第 10 节，真实格子跨到 11 节，核对页可改
    // 周二 5 门：换行拆开的门牌号要拼回去
    expect(find('计算机系统导论', 2).location, '10-309');
    expect(find('大学英语III-1', 2).location, '3-506');
    expect(find('排球俱乐部-1', 2).location, '排球场', reason: '「场」续接地点');
    expect(find('大学生职业发展与就业指导', 2).startMin, 1040);
    // 周三 4 门：太极拳叠在第 10 节，要和排球第一课堂分开
    expect(find('大学英语III-1', 3).location, '10-503');
    expect(find('高等数学(1)(1 II)-1', 3).location, '3-507');
    expect(find('排球第一课堂', 3).location, '一啪');
    final tai = find('太极拳第一周', 3);
    expect(tai.startMin, 1110); // 第 10 节
    // 周四 5 门 + 周五 2 门
    expect(find('形势与政策-1', 4).location, '3-202');
    expect(find('礼仪培训', 4).location, '4-201');
    expect(find('数字电路与数字逻辑', 5).startMin, 625);
    expect(find('计算机系统导论', 5).startMin, 830);
    // 周六周日没课；老师兜底不许吃掉课名片段
    expect(list.where((c) => c.weekday == 6 || c.weekday == 7), isEmpty);
    expect(list.every((c) => c.teacher.isEmpty), true);
  });
}

/// 模拟「WakeUp 式彩色格子」截图（列与列之间有白色缝隙、格内文字居中、
/// 节次标签列在最左）。旧版靠表头锚点中点切列，在这类截图上会把
/// 相邻列粘成一列（20 多门课只认出 6 门）；现在用内容 x 投影列带切列。
List<OcrTextLine> mockWakeUpTimetable({bool dropWeekendHeaders = false}) {
  const labelX = 56.0;
  double colX(int wd) => 190.0 + (wd - 1) * 200.0;
  const rowH = 96.0;
  double rowTop(int p) => 300.0 + (p - 1) * rowH;
  final lines = <OcrTextLine>[];
  // 表头：周X + 日期（周三列头是「今天」）
  for (var wd = 1; wd <= 7; wd++) {
    if (dropWeekendHeaders && wd >= 6) continue; // 周六/周日列头没认出来
    lines.add(OcrTextLine(wd == 3 ? '今天' : '周$wd', colX(wd) - 36, 240, colX(wd) + 36, 272));
    lines.add(OcrTextLine('11/${8 + wd}', colX(wd) - 36, 272, colX(wd) + 36, 300));
  }
  // 节次数字（窄窄地贴在最左边）
  for (var p = 1; p <= 12; p++) {
    lines.add(OcrTextLine('$p', labelX - 10, rowTop(p) + 8, labelX + 10, rowTop(p) + 34));
  }
  // 格子：文字在格内居中，格子之间留缝隙（列宽 190，相邻列中心差 200）
  void cell(int wd, int startP, List<String> textLines) {
    final cx = colX(wd);
    final top = rowTop(startP) + 20; // 文字在格内大致居中
    for (var j = 0; j < textLines.length; j++) {
      final w = math.min(textLines[j].length * 22.0, 170.0); // 格内放不下会换行，不会跨列
      lines.add(OcrTextLine(textLines[j], cx - w / 2, top + j * 30, cx + w / 2, top + j * 30 + 26));
    }
  }

  cell(1, 1, ['大学生', '心理健康', '教育@4-10']);
  cell(1, 3, ['C 语言', '程序设计', '基础@10-3']);
  cell(1, 5, ['计算机', '系统导', '论@7-406']);
  cell(1, 7, ['数字电', '路与数', '字逻辑@6-50']);
  cell(1, 9, ['思想道', '德与法', '治@5-302']);
  cell(2, 1, ['计算机', '系统导', '论@309']);
  cell(2, 3, ['大学英语', 'III-1@3-506']);
  cell(2, 5, ['数字电', '路与数', '字逻辑@1-50']);
  cell(2, 7, ['排球俱', '乐部-1', '@排球场']);
  cell(2, 9, ['大学生', '职业发展', '与就业指导']);
  cell(3, 1, ['大学英语', 'III-1@10-', '503']);
  cell(3, 3, ['高等数学', 'III-1@3-507']);
  cell(3, 9, ['排球第', '一课堂', '@一啪']);
  cell(4, 1, ['高等数学', 'III-1@3-506']);
  cell(4, 3, ['C 语言', '程序设计', '基础@3-40']);
  cell(4, 5, ['C 语言', '程序设计', '基础@2-30']);
  cell(4, 7, ['形势与', '政策-1', '@3-202']);
  cell(4, 9, ['礼仪培', '训@4-201']);
  cell(6, 3, ['数字电', '路与数', '字逻辑@6-50']);
  cell(6, 5, ['计算机', '系统导', '论@7-406']);
  return lines;
}

void wakeUpFormatTests() {
  void expectAllParsed(List<Course> list) {
    expect(list.length, 20, reason: '20 门课一门不少，也没有跨列拼接');
    Course find(String name, int wd) =>
        list.firstWhere((c) => c.name == name && c.weekday == wd);

    final psych = find('大学生心理健康教育', 1);
    expect(psych.startMin, 510); // 第1-2节
    expect(psych.endMin, 605);
    expect(psych.location, '4-10');

    final c1 = find('C 语言程序设计基础', 1);
    expect(c1.location, '10-3');
    expect(c1.startMin, 625);

    final pe = find('排球俱乐部-1', 2);
    expect(pe.location, '排球场');
    expect(pe.startMin, 930); // 第7-8节

    final en = find('大学英语III-1', 3);
    expect(en.location, '10-503', reason: '@10- + 503 续接');

    final cs = list.where((c) => c.name == 'C 语言程序设计基础' && c.weekday == 4).toList();
    expect(cs.length, 2);
    expect(cs[0].location, '3-40');
    expect(cs[1].location, '2-30');
    expect(cs[1].startMin, 830); // 第5-6节

    // 名字没有被跨列拼接（拼接会产生超长乱名）
    for (final c in list) {
      expect(c.name.length, lessThan(16), reason: '名字可疑: ${c.name}');
    }
    expect(list.where((c) => c.weekday == 5 || c.weekday == 7), isEmpty);
  }

  test('WakeUp 式截图：列带切列，20 门课全认出', () {
    final lines = mockWakeUpTimetable();
    final anchors = headerAnchors(lines);
    expect(anchors.length, 7);
    final (list, _) = gridFromOcrLines(lines, anchors, gdut);
    expectAllParsed(list);
  });

  test('周六/周日列头没认出来也能按位置补齐星期', () {
    final lines = mockWakeUpTimetable(dropWeekendHeaders: true);
    final anchors = headerAnchors(lines);
    expect(anchors.length, 5);
    final (list, _) = gridFromOcrLines(lines, anchors, gdut);
    expectAllParsed(list);
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
  weeklyWorkbookTests();
  mergedCellTests();
}

/// 教务导出 xlsx 常用「纵向合并单元格」表示连堂课：
/// 值只在合并区域首行（第1节行），跨度信息靠 mergeCells 提供。
void mergedCellTests() {
  List<List<String>> weekGrid() => [
        ['节次\\星期', '周一', '周二', '周三', '周四', '周五', '周六', '周日'],
        ['第1节', '', '设计造型\n设工(东)-601', '', '', '', '', ''], // C2 合并到 C5
        ['第2节', '', '', '', '', '', '', ''],
        ['第3节', '', '', '', '国家安全教育\n5-102', '', '', ''], // E4 合并到 E5
        ['第4节', '', '', '', '', '', '', ''],
        ['第5节', '', '', '', '', '', '', ''],
        ['第6节', '大学英语(1)\n7-303', '体育(1)', '', '', '', '', ''], // B7:B8 / C7:C8
        ['第7节', '', '', '', '', '', '', ''],
        ['第8节', '', '', '', '', '', '', ''],
        ['第9节', '', '', '', '', '', '', ''],
        ['第10节', '', '', '', '', '大学生健康教育\n5-102', '', ''], // F11:F13
        ['第11节', '', '', '', '', '', '', ''],
        ['第12节', '', '', '', '', '', '', ''],
      ];

  test('合并单元格：连堂课跨节到合并区域末行', () {
    final grid = weekGrid();
    final spans = <(int, int), int>{
      (1, 2): 4, // C2:C5 第1-4节
      (3, 4): 2, // E4:E5 第3-4节
      (6, 1): 2, // B7:B8 第6-7节
      (6, 2): 2, // C7:C8 第6-7节
      (10, 5): 3, // F11:F13 第10-12节
    };
    final list = parseGrid(grid, gdut, rowSpans: spans);
    Course find(String name, int wd) =>
        list.firstWhere((c) => c.name.contains(name) && c.weekday == wd);
    // 设计造型：周二第1-4节（510~720）
    final dsg = find('设计造型', 2);
    expect(dsg.startMin, gdut[0].$1);
    expect(dsg.endMin, gdut[3].$2);
    expect(dsg.location, '设工(东)-601');
    // 国家安全教育：周四第3-4节
    final sec = find('国家安全教育', 4);
    expect(sec.startMin, gdut[2].$1);
    expect(sec.endMin, gdut[3].$2);
    // 大学英语：周一第6-7节
    final en = find('大学英语', 1);
    expect(en.startMin, gdut[5].$1);
    expect(en.endMin, gdut[6].$2);
    expect(en.location, '7-303');
    // 体育：周二第6-7节
    final pe = find('体育', 2);
    expect(pe.startMin, gdut[5].$1);
    expect(pe.endMin, gdut[6].$2);
    // 大学生健康教育：周五第10-12节
    final health = find('健康教育', 5);
    expect(health.startMin, gdut[9].$1);
    expect(health.endMin, gdut[11].$2);
  });

  test('不带 spans 时保持旧行为（格子=首行单节）', () {
    final list = parseGrid(weekGrid(), gdut);
    final dsg = list.firstWhere((c) => c.name.contains('设计造型') && c.weekday == 2);
    expect(dsg.endMin, gdut[0].$2); // 只有第1节
  });
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

void friend2FormatTests() {  test('紧贴格子 + 换行拆开的门牌号 + 「+」按钮的课表截图', () {
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

/// 「每周一页」工作簿：模拟真实导出文件——20 个 sheet（第1周~第20周），
/// 大多数周没课，只有第 5~7 周有一门 体育(1)（周二第6节）。
void weeklyWorkbookTests() {
  List<List<String>> weekSheet(List<String> courseCells) {
    final header = ['节次\\星期', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final rows = <List<String>>[header];
    for (var i = 0; i < 12; i++) {
      final row = List<String>.filled(8, '');
      row[0] = '第${i + 1}节';
      if (i >= 5 && i - 5 < courseCells.length) row[2] = courseCells[i - 5]; // 周二列，从第6节起
      rows.add(row);
    }
    return rows;
  }

  test('每周一页的 xlsx：第一个 sheet 没课也能聚合出全部课程', () {
    final sheets = <String, List<List<String>>>{};
    for (var w = 1; w <= 20; w++) {
      sheets['第$w周'] = weekSheet(
          (w >= 5 && w <= 7) ? ['体育(1)'] : <String>[]);
    }
    final list = aggregateWorkbook(sheets, gdut);
    expect(list.length, 1);
    final pe = list.first;
    expect(pe.name, '体育(1)');
    expect(pe.weekday, 2); // 周二列
    expect(pe.startMin, 880); // 第6节
    expect(pe.endMin, 925);
    expect(pe.weekStart, 5);
    expect(pe.weekEnd, 7);
  });

  test('普通单 sheet 工作簿不受影响', () {
    final sheets = <String, List<List<String>>>{
      '课程表': [
        ['节次\\星期', '周一', '周二', '周三', '周四', '周五'],
        ['第1-2节', '高等数学 1-16周 教404', '', '大学英语 2-17周 文B302', '', ''],
        ['第3-4节', '', '', '', '', '体育 3-16周 操场'],
      ],
    };
    final list = aggregateWorkbook(sheets, gdut);
    expect(list.length, 3);
    expect(list.any((c) => c.name.contains('高等数学') && c.weekStart == 1 && c.weekEnd == 16), true);
  });

  test('sheet 名不带周次时直接并入；格子自带周次优先于 sheet 名', () {
    final sheets = <String, List<List<String>>>{
      '汇总': [
        ['节次\\星期', '周一', '周二'],
        ['第1-2节', '高数', ''],
      ],
      '第3周': [
        ['节次\\星期', '周一', '周二'],
        ['第1-2节', '', '英语 5-10周'],
      ],
      '第4周': [
        ['节次\\星期', '周一', '周二'],
        ['第1-2节', '', '英语 5-10周'],
      ],
    };
    final list = aggregateWorkbook(sheets, gdut);
    expect(list.length, 2);
    final math = list.firstWhere((c) => c.name.contains('高数'));
    expect(math.weekStart, 1);
    final en = list.firstWhere((c) => c.name.contains('英语'));
    expect(en.weekStart, 5); // 格子里写了 5-10周，优先于 sheet 名
    expect(en.weekEnd, 10);
  });
}


/// 「小程序课表截图」的 element 级 OCR 模拟。
/// 这类截图 ML Kit 会把同一水平带的多个格子横向合并成 line，
/// 但 element（词组）各自带独立坐标。模拟：表头「周一~周日」+ 日期、
/// 周三列头是「今天」、裸数字行标签、课名换行拆开、教室 @ 门牌号
/// （个别门牌号跨行拆成 "@10-5" + "03"）。
void elementLevelTests() {
  double colX(int wd) => 100.0 + (wd - 1) * 100.0;
  OcrTextLine el(String t, double cx, double top, {double w = 60, double h = 20}) =>
      OcrTextLine(t, cx - w / 2, top, cx + w / 2, top + h);

  test('element 级网格：今天列 + 裸数字标签 + 换行课名 + 拆行门牌号', () {
    final elems = <OcrTextLine>[
      // 表头：节/数 + 周一~周日 + 日期，周三列头是「今天」
      el('节', 20, 40, w: 16), el('数', 20, 64, w: 16),
      for (var wd = 1; wd <= 7; wd++) ...[
        el(wd == 3 ? '今天' : '周$wd', colX(wd), 40, w: 44),
        el('11/${8 + wd}', colX(wd), 64, w: 44),
      ],
      // 行标签 1~12（裸数字）
      for (var p = 1; p <= 12; p++) el('$p', 20, 90.0 + (p - 1) * 55, w: 14),
      // 周一 1-2节：大学生心理健康教育 @4-10（换行拆开）
      el('大学生', colX(1), 92), el('心理健康', colX(1), 116), el('教育', colX(1), 140), el('@4-10', colX(1), 164),
      // 周一 3-4节：C语言程序设计基础 @10-36
      el('C语言', colX(1), 200), el('程序设计', colX(1), 224), el('基础', colX(1), 248), el('@10-36', colX(1), 272),
      // 周二 1-2节：计算机系统导论 @10-309
      el('计算机', colX(2), 92), el('系统导论', colX(2), 116), el('@10-309', colX(2), 140),
      // 周三(今天) 1-2节：大学英语III-1 @10-503（门牌号拆两行）
      el('大学英语', colX(3), 92), el('III-1', colX(3), 116, w: 40), el('@10-5', colX(3), 140), el('03', colX(3), 164, w: 26),
      // 周四 1-2节：高等数学(1)(III)-1 @3-506
      el('高等数学', colX(4), 92), el('(1)(III)-1', colX(4), 116, w: 70), el('@3-506', colX(4), 140),
      // 周三 3-4节：高等数学(1)(III)-1 @3-507
      el('高等数学', colX(3), 200), el('(1)(III)-1', colX(3), 224, w: 70), el('@3-507', colX(3), 248),
      // 周五 9-10节（跨两行的大格子，文字只在上半部分）
      el('大学生', colX(5), 530), el('职业发展', colX(5), 554), el('与就业指导', colX(5), 578),
    ];

    final anchors = headerAnchors(elems);
    expect(anchors.length, 7, reason: '7 个列头锚点（周三靠日期/今天）');
    final (list, detected) = gridFromOcrLines(elems, anchors, gdut);
    expect(detected, isNull, reason: '行标签没有时间信息');
    List<Course> find(int wd, String name) =>
        list.where((c) => c.weekday == wd && c.name.contains(name)).toList();
    final psych = find(1, '心理健康');
    expect(psych.length, 1);
    expect(psych.first.startMin, gdut[0].$1);
    expect(psych.first.endMin, gdut[1].$2, reason: '跨 1-2 节');
    expect(psych.first.location, '4-10');
    final cLang = find(1, 'C语言');
    expect(cLang.first.location, '10-36');
    expect(cLang.first.startMin, gdut[2].$1);
    final sysIntro = find(2, '系统导论');
    expect(sysIntro.first.location, '10-309');
    final en = find(3, '大学英语');
    expect(en.first.location, '10-503', reason: '@10-5 + 03 续接');
    final math = find(4, '高等数学');
    expect(math.first.location, '3-506');
    final career = find(5, '职业发展');
    expect(career.first.startMin, gdut[8].$1);
    expect(career.first.endMin, gdut[9].$2, reason: '跨 9-10 节');
    expect(list.where((c) => c.weekday == 6 || c.weekday == 7).length, 0,
        reason: '周六周日没课，不应凭空造课');
  });
}
