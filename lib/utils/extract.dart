// 通知「重点提炼」：纯本地规则，不联网、不上传。
// v2：按要素结构化提取 —— 时间 / 地点 / 谁 / 开始 / 截止（最晚），
// 时间、地点、人名尽量完整抓取，再附上其余重要句子（谁做了什么）。

class ExtractResult {
  final List<String> keyPoints;
  final List<String> links;
  final List<String> deadlines;

  const ExtractResult({this.keyPoints = const [], this.links = const [], this.deadlines = const []});

  bool get isEmpty => keyPoints.isEmpty && links.isEmpty && deadlines.isEmpty;
}

final RegExp _urlRe = RegExp(
  r'((?:https?://|www\.)[^\s，。；、）)\]】"”’]+)'
  r'|((?:pan\.baidu\.com|yun\.baidu\.com|docs\.qq\.com|kdocs\.cn|shimo\.im|wjx\.cn|jinshuju\.net|'
  r'jinshuju\.com|qq\.com|bilibili\.com|github\.com|chaoxing\.com|zhihuishu\.com|icve\.com)[^\s，。；、）)\]】"”’]*)',
);

final RegExp _dateRe = RegExp(
  r'(\d{4}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?)'
  r'|(\d{1,2}\s*月\s*\d{1,2}\s*[日号])'
  r'|(\d{1,2}\s*[:：]\s*\d{2})'
  r'|(第?\s*\d{1,2}\s*周)'
  r'|(周[一二三四五六日天])'
  r'|(星期[一二三四五六日天])'
  r'|(今天|明天|后天|本周|下周|本周内|今明两天)',
);

/// 完整时间片段：日期(+星期)(+时刻)、相对词(+时刻)、单独时刻
final RegExp _spanRe = RegExp(
  r'((\d{4}\s*[年\-/.])?\s*\d{1,2}\s*[月\-/.]\s*\d{1,2}\s*[日号]?\s*(（?\s*[周星期]\s*[一二三四五六日天]\s*）?)?\s*(晚上|中午|早上|早晨|凌晨|晚|[上下]?午)?\s*\d{1,2}\s*[:：点]\s*\d{1,2}\s*分?)'
  r'|((今天|明天|后天|本周|下周)\s*(晚上|中午|早上|早晨|凌晨|晚|[上下]?午)?\s*\d{1,2}\s*[:：点]\s*\d{1,2}\s*分?)'
  r'|((\d{4}\s*[年\-/.])?\s*\d{1,2}\s*[月\-/.]\s*\d{1,2}\s*[日号]\s*(（?\s*[周星期]\s*[一二三四五六日天]\s*）?)?)'
  r'|((今天|明天|后天|本周内|本周|下周|本月|月底)\s*之前?)'
  r'|(\d{1,2}\s*[:：]\s*\d{2}\s*分?)'
  r'|(周[一二三四五六日天]|星期[一二三四五六日天])',
);

/// 地点：教室编号（T-303 / 教工(东)-601 / A栋101）、场馆词、线上会议
final RegExp _placeRe = RegExp(
  r'([A-Za-z\u4e00-\u9fa5]{1,6}\s*[（(]\s*[A-Za-z\u4e00-\u9fa5]{1,4}\s*[)）])?\s*[-—~]?\s*[A-Za-z]?\s*[-—~]?\s*\d{3,4}\s*(室|教室)?'
  r'|[\u4e00-\u9fa5A-Za-z0-9]{2,12}(教学楼|实验楼|报告厅|会议室|阶梯教室|教室|图书馆|体育馆|操场|运动场|实验室|办公室|活动中心|学术报告厅|广场|食堂|宿舍|机房|考场)'
  r'|(腾讯会议|钉钉会议|会议号|腾讯会议号)\s*[:：]?\s*\d{9,12}'
  r'|(线上进行|线上开展|线上|直播间|QQ群课堂|网络平台)',
);

/// 人名：X老师 / 找/联系/负责 + 姓名 + 称呼 / 联系人：XXX
final RegExp _personRe = RegExp(
  r'((找|联系|咨询|报送|发送给|发给|交给|上交?给)\s*[\u4e00-\u9fa5]{2,4}\s*(老师|同学|导员|辅导员|主任|部长|主席|书记|干事|经理|班长|组长))'
  r'|((负责人|联系人|组织人|对接人)\s*[:：]?\s*[\u4e00-\u9fa5]{2,4}\s*(老师|同学|导员|辅导员|主任|部长|主席|书记|干事)?)'
  r'|([\u4e00-\u9fa5]{1,3}(老师|导员|辅导员|教授|班主任))'
  r'|((学习委员|班长|团支书|组织委员|宣传委员|生活委员|体育委员|课代表)\s*[\u4e00-\u9fa5]{2,3}(同学)?(?=[，。；、\s！？]|$))',
);

const List<String> _hotWords = [
  '截止', '报名', '提交', '上交', '交到', '缴纳', '缴费', '费用',
  '考试', '测验', '测试', '答辩', '面试', '笔试', '签到', '点名',
  '地点', '教室', '线上', '会议号', '腾讯会议', '时间', '开始', '结束',
  '要求', '注意', '务必', '必须', '重要', '紧急', '取消', '延期', '改期',
  '材料', '附件', '文件', '表格', '链接', '群文件', '二维码', '分组', '组队',
  '名额', '人数', '资格', '审核', '名单', '成绩', '证书',
];

/// 把一段通知原文拆成句子（按换行和中文标点断句）
List<String> _splitSentences(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final out = <String>[];
  for (final line in normalized.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.length <= 60) {
      out.add(trimmed);
    } else {
      final parts = trimmed.split(RegExp(r'[。！？；;!?]'));
      for (final p in parts) {
        final t = p.trim();
        if (t.length >= 4) out.add(t);
      }
    }
  }
  return out;
}

String _clean(String s) {
  var t = s;
  // 只删列表符号 + 「1.」式编号，不能把开头的年份数字删掉
  t = t.replaceAll(RegExp(r'^[\s\-—•·*※]+(?:\d{1,2}[\.、]\s*)?'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  if (t.length > 90) t = '${t.substring(0, 90)}…';
  return t.trim();
}

/// 抓句子里所有完整时间片段（按出现顺序、去重）
List<String> _spansOf(String s) {
  final out = <String>[];
  for (final m in _spanRe.allMatches(s)) {
    final v = m.group(0)!.trim().replaceAll(RegExp(r'\s+'), '');
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out;
}

List<String> _placesOf(String s) {
  final out = <String>[];
  for (final m in _placeRe.allMatches(s)) {
    var v = m.group(0)!.trim().replaceAll(RegExp(r'\s+'), '');
    v = v.replaceFirst(RegExp(r'^(在|于|到|至|地[点址]|位置[:：])'), '');
    if (v.length < 3 && v != '线上') continue; // 过滤误抓的短数字
    if (RegExp(r'^\d+$').hasMatch(v)) continue;
    if (!out.contains(v)) out.add(v);
  }
  return out;
}

List<String> _personsOf(String s) {
  final out = <String>[];
  for (final m in _personRe.allMatches(s)) {
    final v = m.group(0)!.trim();
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out;
}

bool _hasStartWord(String s) =>
    RegExp(r'(开始|召开|举行|开考|开赛|开始时间|进行|开幕|启动|开课|上课|考试时间|比赛时间)').hasMatch(s);

bool _hasDeadlineWord(String s) =>
    RegExp(r'(截止|之前|以前|前完成|前提交|前上交|最晚|不晚于|逾期|deadline)').hasMatch(s);

/// 核心提炼：先抽要素（开始/截止/时间/地点/谁），再补重要句子
ExtractResult extractNotice(String text, {int maxPoints = 8}) {
  if (text.trim().isEmpty) return const ExtractResult();

  final links = <String>[];
  for (final m in _urlRe.allMatches(text)) {
    var url = m.group(0)!.trim();
    url = url.replaceAll(RegExp(r'[，。；、）)\]】"”’]+$'), '');
    if (url.isEmpty) continue;
    if (!url.startsWith('http')) url = 'https://$url';
    if (!links.contains(url)) links.add(url);
  }

  final sentences = _splitSentences(text);

  final starts = <String>[];
  final deadlines = <String>[];
  final times = <String>[];
  final places = <String>[];
  final persons = <String>[];
  final scored = <MapEntry<int, String>>[];

  for (final raw in sentences) {
    final s = _clean(raw);
    if (s.isEmpty) continue;
    if (_urlRe.hasMatch(s) && s.length < 30) continue; // 纯链接行跳过

    // —— 要素抽取（时间/地点/人名要完整）——
    final spans = _spansOf(s);
    final pls = _placesOf(s);
    final pns = _personsOf(s);
    final isStart = _hasStartWord(s) && spans.isNotEmpty;
    final isDeadline = _hasDeadlineWord(s) && spans.isNotEmpty;

    if (isStart) {
      final line = '🚩 开始：${spans.join(' 或 ')}${pls.isEmpty ? '' : ' · ${pls.first}'}';
      if (!starts.contains(line)) starts.add(line);
    }
    if (isDeadline) {
      final latest = RegExp(r'(最晚|不晚于|逾期)').hasMatch(s);
      final line = '⏳ 截止：${spans.join(' 或 ')}${latest ? '（最晚）' : ''}';
      if (!deadlines.contains(line)) deadlines.add(line);
    }
    if (!isStart && !isDeadline && spans.isNotEmpty) {
      for (final v in spans) {
        final line = '⏰ 时间：$v';
        if (!times.contains(line)) times.add(line);
      }
    }
    for (final v in pls) {
      final line = '📍 地点：$v';
      if (!places.contains(line)) places.add(line);
    }
    for (final v in pns) {
      final line = '👤 谁：$v';
      if (!persons.contains(line)) persons.add(line);
    }

    // —— 重要性打分（保留"谁做了什么"的原句）——
    var score = 0;
    for (final w in _hotWords) {
      if (s.contains(w)) score += 2;
    }
    if (_dateRe.hasMatch(s)) score += 3;
    if (isDeadline || isStart) score += 3;
    if (RegExp(r'[0-9]{1,2}\s*[:：]\s*[0-9]{2}').hasMatch(s)) score += 1;
    if (score > 0) scored.add(MapEntry(score, s));
  }

  // 组装：开始 → 截止 → 时间 → 地点 → 谁 → 其余重要句子
  final points = <String>[];
  void pushAll(List<String> list) {
    for (final p in list) {
      if (!points.contains(p)) points.add(p);
    }
  }

  pushAll(starts.take(2).toList());
  pushAll(deadlines.take(2).toList());
  pushAll(times.take(3).toList());
  pushAll(places.take(3).toList());
  pushAll(persons.take(3).toList());

  scored.sort((a, b) => b.key.compareTo(a.key));
  for (final e in scored) {
    if (points.length >= maxPoints) break;
    // 要素行已经覆盖的信息，句子原样再放一条（谁做了什么需要完整句子）
    points.add(e.value);
  }

  return ExtractResult(
    keyPoints: points.take(maxPoints).toList(),
    links: links,
    deadlines: deadlines
        .map((e) => e.replaceFirst('⏳ 截止：', ''))
        .take(3)
        .toList(),
  );
}

/// 想不出标题时，用第一句当标题
String suggestTitle(String text) {
  final sentences = _splitSentences(text);
  if (sentences.isEmpty) return '未命名通知';
  final first = _clean(sentences.first);
  return first.length <= 24 ? first : '${first.substring(0, 24)}…';
}
