import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';

/// 手机当小型服务器：电脑浏览器连同一个 Wi-Fi（或手机热点）就能打开，
/// 查看课程/待办/比赛战绩/灵感/笔记/总结，导出 CSV、下载备份、上传备份恢复、下载附件。
/// 默认开启 4 位访问码，同一个 Wi-Fi 下的其他人没有码就打不开。
class LanSyncServer {
  LanSyncServer._();
  static final LanSyncServer I = LanSyncServer._();

  static const List<int> _candidatePorts = [8731, 8899, 9099];

  HttpServer? _server;
  String _primaryIp = '';
  List<String> _otherIps = const [];
  String? _code;
  final Set<String> _sessions = {};
  final Random _rand = Random();

  bool get running => _server != null;
  int get port => _server?.port ?? 0;
  String get primaryIp => _primaryIp;
  List<String> get otherIps => _otherIps;
  bool get needsCode => _code != null;
  String get accessCode => _code ?? '';
  String get url => running ? 'http://$_primaryIp:$port' : '';
  int get sessionCount => _sessions.length;

  Future<void> start(AppState state, {bool requireCode = true}) async {
    if (_server != null) return;
    final ips = await _localIps();
    if (ips.isEmpty) {
      throw '没找到局域网地址：先打开 Wi-Fi 或手机热点，再试一次';
    }
    _primaryIp = ips.first;
    _otherIps = ips.skip(1).toList();
    _sessions.clear();
    _code = requireCode ? _newCode() : null;

    HttpServer? server;
    Object? lastError;
    for (final p in _candidatePorts) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (server == null) {
      throw '端口都被占用了：$lastError';
    }
    _server = server;
    server.listen(
      (req) => _handle(req, state),
      onError: (Object e) => stderr.writeln('lan sync error: $e'),
    );
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _primaryIp = '';
    _otherIps = const [];
    _code = null;
    _sessions.clear();
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }

  /// 换一个新访问码：已连上的电脑需要重新输入
  void rotateCode() {
    _code = _code == null ? null : _newCode();
    _sessions.clear();
  }

  /// 开关访问码（服务运行中也能改）
  void setRequireCode(bool require) {
    if (require) {
      _code ??= _newCode();
    } else {
      _code = null;
    }
    _sessions.clear();
  }

  String _newCode() => (_rand.nextInt(9000) + 1000).toString();

  String _newToken() => List.generate(4, (_) => _rand.nextInt(1 << 32).toRadixString(16)).join();

  // ------------------------------------------------------------ 路由
  Future<void> _handle(HttpRequest req, AppState state) async {
    try {
      final path = req.uri.path;
      final method = req.method;

      // 登录
      if (path == '/login') {
        if (method == 'POST') {
          final body = await utf8.decoder.bind(req).join();
          var input = '';
          try {
            input = (Uri.splitQueryString(body)['code'] ?? '').trim();
          } catch (_) {
            input = '';
          }
          if (_code != null && input == _code) {
            final token = _newToken();
            _sessions.add(token);
            req.response.headers.add('set-cookie', 'sid=$token; Path=/; Max-Age=86400; SameSite=Lax');
            req.response.statusCode = 303;
            req.response.headers.set('location', '/');
          } else {
            req.response.statusCode = 401;
            _html(req.response, _loginPage('访问码不对，看一眼手机屏幕上的 4 位数字'));
          }
          await req.response.close();
          return;
        }
        _html(req.response, _loginPage(null));
        await req.response.close();
        return;
      }

      if (path == '/logout') {
        final token = _tokenOf(req);
        if (token != null) _sessions.remove(token);
        req.response.headers.add('set-cookie', 'sid=; Path=/; Max-Age=0');
        req.response.statusCode = 303;
        req.response.headers.set('location', '/');
        await req.response.close();
        return;
      }

      if (!_authorized(req)) {
        if (path == '/' || path == '/index.html') {
          _html(req.response, _loginPage(null));
        } else {
          req.response.statusCode = 401;
          _text(req.response, '需要访问码：请先用手机屏幕上显示的 4 位访问码登录');
        }
        await req.response.close();
        return;
      }

      if (method == 'GET' && (path == '/' || path == '/index.html')) {
        _html(req.response, _buildPage(state));
        await req.response.close();
        return;
      }

      if (method == 'GET' && path == '/backup.json') {
        final text = await state.exportBackup();
        req.response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        _attachment(req.response, 'class_reminder_${_stamp()}.json');
        req.response.add(utf8.encode(text));
        await req.response.close();
        return;
      }

      if (method == 'POST' && path == '/restore') {
        final body = await utf8.decoder.bind(req).join();
        try {
          await state.importBackup(body);
          _text(req.response, '恢复成功：手机上的数据已替换为这份备份。可以回到手机上确认。');
        } catch (e) {
          req.response.statusCode = 400;
          _text(req.response, '恢复失败：$e');
        }
        await req.response.close();
        return;
      }

      if (method == 'GET' && path.startsWith('/export/')) {
        final kind = path.substring('/export/'.length);
        String name;
        String content;
        switch (kind) {
          case 'tasks.csv':
            name = '待办清单_${_stamp()}.csv';
            content = _csvTasks(state);
            break;
          case 'courses.csv':
            name = '课程表_${_stamp()}.csv';
            content = _csvCourses(state);
            break;
          case 'summaries.csv':
            name = '总结汇总_${_stamp()}.csv';
            content = _csvSummaries(state);
            break;
          case 'ideas.csv':
            name = '灵感库_${_stamp()}.csv';
            content = _csvIdeas(state);
            break;
          default:
            name = '';
            content = '';
        }
        if (name.isEmpty) {
          req.response.statusCode = 404;
          _text(req.response, '没有这个导出');
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType('text', 'csv', charset: 'utf-8');
        _attachment(req.response, name);
        // BOM：让 Excel 直接认出 UTF-8
        req.response.add(utf8.encode('\uFEFF$content'));
        await req.response.close();
        return;
      }

      if (method == 'GET' && path.startsWith('/files/')) {
        final id = int.tryParse(path.substring('/files/'.length));
        AttachmentItem? item;
        for (final a in state.attachments) {
          if (a.id == id) {
            item = a;
            break;
          }
        }
        if (item == null) {
          req.response.statusCode = 404;
          _text(req.response, '文件不存在');
          await req.response.close();
          return;
        }
        final f = File(item.path);
        if (!await f.exists()) {
          req.response.statusCode = 404;
          _text(req.response, '文件已被清理');
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.parse(_mime(item.ext));
        _attachment(req.response, item.name);
        await req.response.addStream(f.openRead());
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      _text(req.response, '没有这个页面');
      await req.response.close();
    } catch (e) {
      try {
        req.response.statusCode = 500;
        _text(req.response, '出错了：$e');
        await req.response.close();
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest req) {
    if (_code == null) return true;
    final token = _tokenOf(req);
    return token != null && _sessions.contains(token);
  }

  String? _tokenOf(HttpRequest req) {
    final cookie = req.headers.value(HttpHeaders.cookieHeader);
    if (cookie == null) return null;
    for (final part in cookie.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2 && kv[0] == 'sid') return kv[1];
    }
    return null;
  }

  // ------------------------------------------------------------ 页面
  String _buildPage(AppState s) {
    final now = DateTime.now();
    final todayCourses = s.coursesOfDay(now.weekday);
    final pending = s.pending.take(30).toList();
    final ideas = s.ideas.take(30).toList();
    final notes = s.notes.take(20).toList();

    final b = StringBuffer();
    b.writeln('<h1>课表 · 待办 · 比赛 <span class="tag">电脑端</span></h1>');
    b.writeln(
      '<p class="sub">${fmtDate(now)} ${weekdayLabel(now.weekday)} · 第 ${s.currentWeek} 周 · '
      '${hhmmOf(now)} 从手机读取 · 只在局域网内传输，不经过任何服务器</p>',
    );

    b.writeln('<div class="stats">');
    b.writeln('<div><b>${s.courses.length}</b><span>门课</span></div>');
    b.writeln('<div><b>${s.pending.length}</b><span>未完成待办</span></div>');
    b.writeln('<div><b>${s.ideaCount}</b><span>条灵感/痛点/想法</span></div>');
    b.writeln('<div><b>${s.pastCompCount}</b><span>场参赛</span></div>');
    b.writeln('<div><b>${s.awardedCount}</b><span>次获奖</span></div>');
    b.writeln('<div><b>${s.notes.length}</b><span>篇笔记</span></div>');
    b.writeln('</div>');
    b.writeln(
      '<p class="sub">今日专注 ${_hm(s.todayFocusSeconds)} · 本周 ${_hm(s.weekFocusSeconds)}</p>',
    );

    b.writeln('<nav class="nav">');
    b.writeln('<a href="#today">今日课程</a>');
    b.writeln('<a href="#tasks">待办</a>');
    b.writeln('<a href="#comps">比赛</a>');
    b.writeln('<a href="#sums">总结</a>');
    b.writeln('<a href="#ideas">灵感</a>');
    b.writeln('<a href="#notes">笔记</a>');
    b.writeln('</nav>');

    b.writeln('<div class="actions">');
    b.writeln('<a class="btn primary" href="/backup.json">下载完整备份（.json）</a>');
    b.writeln('<a class="btn" href="/export/tasks.csv">待办.csv</a>');
    b.writeln('<a class="btn" href="/export/courses.csv">课程表.csv</a>');
    b.writeln('<a class="btn" href="/export/summaries.csv">总结.csv</a>');
    b.writeln('<a class="btn" href="/export/ideas.csv">灵感.csv</a>');
    b.writeln('<button class="btn" id="reload">刷新</button>');
    b.writeln('<button class="btn" id="print">打印 / 存 PDF</button>');
    b.writeln('<label class="switch"><input type="checkbox" id="auto"> 每 30 秒自动刷新</label>');
    if (needsCode) b.writeln('<a class="btn" href="/logout">退出登录</a>');
    b.writeln('</div>');

    // 今日课程
    b.writeln('<h2 id="today">今日课程</h2>');
    if (todayCourses.isEmpty) {
      b.writeln('<p class="empty">今天没有课。</p>');
    } else {
      b.writeln('<table><tr><th>时间</th><th>课程</th><th>地点</th><th>教师</th></tr>');
      for (final c in todayCourses) {
        b.writeln('<tr><td class="mono">${hhmm(c.startMin)}–${hhmm(c.endMin)}</td>'
            '<td>${_esc(c.name)}</td><td>${_esc(c.location)}</td><td>${_esc(c.teacher)}</td></tr>');
      }
      b.writeln('</table>');
    }

    // 待办
    b.writeln('<h2 id="tasks">未完成待办</h2>');
    if (pending.isEmpty) {
      b.writeln('<p class="empty">没有未完成的待办。</p>');
    } else {
      b.writeln('<ul class="list">');
      for (final t in pending) {
        final due = t.dueAt == null ? '未设截止' : '截止 ${fmtDateTime(t.dueAt)}';
        final overdue = isOverdueAt(t.dueAt, now: now);
        final eval = t.hasEvaluation
            ? '<small>评价 ${t.reviewer.isEmpty ? '' : '${_esc(t.reviewer)} · '}'
                '${t.score.isEmpty ? '已评价' : '${_esc(t.score)} 分'}'
                '${t.reviewNote.isEmpty ? '' : ' · ${_esc(t.reviewNote)}'}</small>'
            : '';
        final sum = t.hasSummary ? '<small>总结：${_esc(t.summary.replaceAll('\n', ' '))}</small>' : '';
        b.writeln('<li><span class="dot" style="background:${_hex(t.type.color.toARGB32())}"></span>'
            '<div><b>${_esc(t.title)}</b>'
            '<small>${t.type.label} · ${_esc(due)}${overdue ? ' · <span class="warn">已逾期</span>' : ''}</small>'
            '$eval$sum'
            '</div></li>');
      }
      b.writeln('</ul>');
    }

    // 比赛与战绩
    b.writeln('<h2 id="comps">比赛与战绩</h2>');
    final ups = s.upcomingCompetitions;
    final pasts = s.pastCompetitions;
    if (ups.isEmpty && pasts.isEmpty) {
      b.writeln('<p class="empty">还没有记录比赛。</p>');
    } else {
      if (ups.isNotEmpty) {
        b.writeln('<ul class="list">');
        for (final c in ups.take(10)) {
          final anchor = c.startAt ?? c.signupDeadline;
          final left = anchor == null ? '' : '<span class="warn">${leftText(anchor)}</span>';
          b.writeln('<li><span class="dot" style="background:#4C6FFF"></span>'
              '<div><b>${_esc(c.name)}</b>'
              '<small>${_esc(c.stage)} · ${_esc(c.level)}${c.location.isEmpty ? '' : ' · ${_esc(c.location)}'}'
              '${anchor == null ? '' : ' · ${fmtDateTime(anchor)}'} · $left</small>'
              '</div></li>');
        }
        b.writeln('</ul>');
      }
      if (pasts.isNotEmpty) {
        b.writeln('<p class="sub" style="margin:14px 0 8px">参加过的比赛 · 共 ${pasts.length} 场</p>');
        b.writeln('<table><tr><th>比赛</th><th>赛段 / 级别</th><th>时间</th><th>结果</th></tr>');
        for (final c in pasts) {
          final when = c.endAt ?? c.startAt ?? c.resultAt;
          final rc = _hex(compResultColor(c.resultRank).toARGB32());
          final note = [
            if (c.resultNote.isNotEmpty) '<small>${_esc(c.resultNote)}</small>',
            if (c.summary.isNotEmpty) '<small>总结：${_esc(c.summary.replaceAll('\n', ' '))}</small>',
          ].map((v) => '<br>$v').join();
          b.writeln('<tr><td><b>${_esc(c.name)}</b>$note</td>'
              '<td>${_esc(c.stage)}<br><small>${_esc(c.level)}</small></td>'
              '<td class="mono">${when == null ? '—' : fmtDate(when)}</td>'
              '<td><span class="chip" style="color:$rc;background:${rc}1a">${compResultLabel(c.resultRank)}</span></td></tr>');
        }
        b.writeln('</table>');
      }
    }

    // 总结与复盘
    b.writeln('<h2 id="sums">总结与复盘</h2>');
    final sumTasks = s.tasks.where((t) => t.hasSummary).toList()
      ..sort((a, b) => (b.evaluatedAt ?? b.createdAt).compareTo(a.evaluatedAt ?? a.createdAt));
    final sumComps = s.competitions.where((c) => c.summary.trim().isNotEmpty).toList();
    final sumNotes = s.notes.where((n) => n.hasReview).toList();
    final sumIdeas = s.ideas.where((i) => i.hasReview).toList();
    if (sumTasks.isEmpty && sumComps.isEmpty && sumNotes.isEmpty && sumIdeas.isEmpty) {
      b.writeln('<p class="empty">还没有写过总结。做完作业 / 比完赛 / 读完笔记后回去补一句，就会出现在这里。</p>');
    } else {
      for (final t in sumTasks.take(12)) {
        final meta = t.hasEvaluation
            ? '<span class="chip" style="color:#C77D00;background:#C77D001a">'
                '${_esc(t.score.isEmpty ? '已评价' : t.score)}${t.reviewer.isEmpty ? '' : ' · ${_esc(t.reviewer)}'}</span>'
            : '';
        b.writeln('<div class="card"><div class="row">'
            '<span class="chip" style="color:${_hex(t.type.color.toARGB32())};'
            'background:${_hex(t.type.color.toARGB32())}1a">${t.type.label}</span>$meta'
            '<small>${fmtDate(t.evaluatedAt ?? t.dueAt ?? t.createdAt)}</small></div>'
            '<h3>${_esc(t.title)}</h3>'
            '<p class="body">${_esc(t.summary).replaceAll('\n', '<br>')}</p></div>');
      }
      for (final c in sumComps) {
        b.writeln('<div class="card"><div class="row">'
            '<span class="chip" style="color:#C77D00;background:#C77D001a">比赛</span>'
            '<span class="chip" style="color:${_hex(compResultColor(c.resultRank).toARGB32())};'
            'background:${_hex(compResultColor(c.resultRank).toARGB32())}1a">${compResultLabel(c.resultRank)}</span>'
            '<small>${fmtDate(c.resultAt ?? c.endAt ?? c.startAt ?? c.createdAt)}</small></div>'
            '<h3>${_esc(c.name)}</h3>'
            '<p class="body">${_esc(c.summary).replaceAll('\n', '<br>')}</p></div>');
      }
      for (final n in sumNotes) {
        b.writeln('<div class="card"><div class="row">'
            '<span class="chip" style="color:#4C6FFF;background:#4C6FFF1a">笔记</span>'
            '<small>${fmtDate(n.updatedAt)}</small></div>'
            '<h3>${_esc(n.title)}</h3>'
            '${n.review.isEmpty ? '' : '<p class="body">${_esc(n.review).replaceAll('\n', '<br>')}</p>'}'
            '${n.rating > 0 ? '<p style="margin:6px 0 0;font-size:12px;color:#C77D00">${_stars(n.rating)}</p>' : ''}'
            '</div>');
      }
      for (final i in sumIdeas) {
        b.writeln('<div class="card"><div class="row">'
            '<span class="chip" style="color:#7048E8;background:#7048E81a">灵感</span>'
            '<small>${fmtDate(i.updatedAt)}</small></div>'
            '<h3>${_esc(i.title)}</h3>'
            '${i.review.isEmpty ? '' : '<p class="body">${_esc(i.review).replaceAll('\n', '<br>')}</p>'}'
            '${i.rating > 0 ? '<p style="margin:6px 0 0;font-size:12px;color:#C77D00">${_stars(i.rating)}</p>' : ''}'
            '</div>');
      }
    }

    // 灵感
    b.writeln('<h2 id="ideas">灵感 / 痛点 / 想法</h2>');
    if (ideas.isEmpty) {
      b.writeln('<p class="empty">还没有记录。</p>');
    } else {
      for (final i in ideas) {
        final files = s.attachmentsOf('idea', i.id);
        b.writeln('<div class="card"><div class="row"><span class="chip" style="color:${_hex(i.kind.color.toARGB32())};'
            'background:${_hex(i.kind.color.toARGB32())}1a">${i.kind.label}</span>'
            '<small>${fmtDate(i.updatedAt)}</small></div>'
            '<h3>${_esc(i.title)}</h3>');
        if (i.content.isNotEmpty) {
          b.writeln('<p class="body">${_esc(i.content).replaceAll('\n', '<br>')}</p>');
        }
        if (i.hasReview) {
          b.writeln('<p style="margin:6px 0 0;font-size:12px;color:#C77D00">${_stars(i.rating)}'
              '${_esc(i.review).replaceAll('\n', '<br>')}</p>');
        }
        if (files.isNotEmpty) {
          b.writeln('<p class="files">附件：');
          for (final f in files) {
            b.writeln('<a href="/files/${f.id}">${_esc(f.name)}</a>');
          }
          b.writeln('</p>');
        }
        b.writeln('</div>');
      }
    }

    // 笔记
    b.writeln('<h2 id="notes">最近笔记</h2>');
    if (notes.isEmpty) {
      b.writeln('<p class="empty">还没有笔记。</p>');
    } else {
      for (final n in notes) {
        final files = s.attachmentsOf('note', n.id);
        b.writeln('<div class="card"><div class="row"><h3>${_esc(n.title)}</h3>'
            '<small>${fmtDate(n.updatedAt)}</small></div>');
        if (n.content.isNotEmpty) {
          b.writeln('<p class="body">${_esc(n.content).replaceAll('\n', '<br>')}</p>');
        }
        if (n.hasReview) {
          b.writeln('<p style="margin:6px 0 0;font-size:12px;color:#C77D00">${_stars(n.rating)}'
              '${_esc(n.review).replaceAll('\n', '<br>')}</p>');
        }
        if (files.isNotEmpty) {
          b.writeln('<p class="files">附件：');
          for (final f in files) {
            b.writeln('<a href="/files/${f.id}">${_esc(f.name)}</a>');
          }
          b.writeln('</p>');
        }
        b.writeln('</div>');
      }
    }

    // 恢复
    b.writeln('<h2 id="restore">把电脑上的备份恢复到手机</h2>');
    b.writeln(
      '<div class="card"><p class="body">选一个之前从 App 导出的 .json 备份文件，上传后手机上的数据会被<b>整体替换</b>。'
      '建议先在手机上导出一份当前备份，再操作。</p>'
      '<input type="file" id="f" accept=".json,application/json">'
      '<div class="actions"><button class="btn danger" id="up">上传并覆盖手机数据</button></div>'
      '<pre id="msg"></pre></div>',
    );

    b.writeln('<p class="foot">关闭手机上的「同步到电脑」页面，这个网页就打不开了。数据不会离开你的设备。</p>');

    return _wrap(b.toString());
  }

  String _loginPage(String? error) {
    final code = _code;
    if (code == null) {
      return _wrap('<h1>课表 · 待办 <span class="tag">电脑端</span></h1>'
          '<p class="sub">这个页面不需要访问码，直接 <a href="/">进入</a>。</p>');
    }
    return _wrap('''
<div class="login">
  <h1>课表 · 待办 <span class="tag">电脑端</span></h1>
  <p class="sub">在手机上打开「我的 → 同步到电脑」，把这 4 位访问码输进去。</p>
  ${error == null ? '' : '<p class="err">$error</p>'}
  <form method="post" action="/login">
    <input name="code" inputmode="numeric" maxlength="4" autofocus placeholder="4 位访问码">
    <button class="btn primary" type="submit">进入</button>
  </form>
  <p class="sub" style="margin-top:14px">访问码只在本次共享有效，换一次共享就换一个码；不想用可以在手机上关掉。</p>
</div>
''');
  }

  String _wrap(String body) => '''
<!DOCTYPE html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>课表 · 待办 · 比赛 · 电脑端</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body { margin:0; background:#F5F6FA; color:#1A1C22;
    font-family: -apple-system, "Segoe UI", "Microsoft YaHei", "PingFang SC", sans-serif; }
  .wrap { max-width: 820px; margin: 0 auto; padding: 28px 18px 60px; }
  h1 { font-size: 24px; margin: 0 0 6px; }
  h1 .tag { font-size: 11px; vertical-align: middle; background:#4C6FFF; color:#fff;
    border-radius: 6px; padding: 2px 7px; margin-left: 6px; font-weight: 600; }
  h2 { font-size: 16px; margin: 28px 0 10px; scroll-margin-top: 64px; }
  h3 { font-size: 14.5px; margin: 0 0 6px; }
  .sub { color:#6B7280; font-size: 12.5px; margin: 0; line-height: 1.7; }
  .nav { position: sticky; top: 0; z-index: 5; display:flex; gap:6px; flex-wrap: wrap;
    background: rgba(245,246,250,.94); backdrop-filter: blur(8px); padding: 10px 0; margin: 14px 0 4px; }
  .nav a { font-size: 12px; color:#4A4F5C; text-decoration:none; background:#fff;
    border-radius: 9px; padding: 6px 11px; }
  .stats { display:flex; gap:10px; margin: 12px 0; flex-wrap: wrap; }
  .stats div { flex:1 1 120px; background:#fff; border-radius:14px; padding:12px 14px;
    display:flex; flex-direction:column; gap:2px; }
  .stats b { font-size: 22px; color:#4C6FFF; }
  .stats span { font-size: 11.5px; color:#6B7280; }
  .actions { display:flex; gap:10px; flex-wrap: wrap; margin: 12px 0; align-items:center; }
  .btn { display:inline-block; border:0; cursor:pointer; text-decoration:none;
    background:#fff; color:#1A1C22; border-radius:12px; padding:11px 16px; font-size:13px;
    box-shadow: 0 1px 0 rgba(0,0,0,.04); font-family: inherit; }
  .btn.primary { background:#4C6FFF; color:#fff; }
  .btn.danger { background:#D6336C; color:#fff; }
  .switch { font-size: 12px; color:#6B7280; display:flex; align-items:center; gap:6px; }
  table { width:100%; border-collapse: collapse; background:#fff; border-radius:14px; overflow:hidden; }
  th, td { text-align:left; padding:11px 14px; font-size:13px; border-bottom:1px solid #F1F3F5; }
  th { background:#FAFBFC; color:#6B7280; font-weight:600; font-size:11.5px; }
  tr:last-child td { border-bottom:0; }
  .mono { font-variant-numeric: tabular-nums; color:#4C6FFF; font-weight:600; }
  .list { list-style:none; padding:0; margin:0; }
  .list li { display:flex; gap:10px; align-items:flex-start; background:#fff;
    border-radius:14px; padding:12px 14px; margin-bottom:8px; }
  .list b { font-size:13.5px; font-weight:600; }
  .list small { display:block; color:#6B7280; font-size:11.5px; margin-top:3px; }
  .dot { width:8px; height:8px; border-radius:50%; margin-top:6px; flex:0 0 auto; }
  .warn { color:#D6336C; }
  .card { background:#fff; border-radius:14px; padding:14px 16px; margin-bottom:10px; }
  .row { display:flex; align-items:center; justify-content:space-between; gap:10px; }
  .row small { color:#9AA0AD; font-size:11px; }
  .chip { font-size:10.5px; padding:2px 8px; border-radius:7px; font-weight:700; }
  .body { font-size:12.5px; line-height:1.75; color:#4A4F5C; margin: 4px 0 0; }
  .files { font-size:11.5px; margin:8px 0 0; color:#2B8A3E; }
  .files a { color:#1971C2; margin-right:10px; }
  .empty { color:#9AA0AD; font-size:12.5px; }
  .foot { color:#9AA0AD; font-size:11.5px; margin-top:32px; text-align:center; }
  input[type=file] { margin:10px 0; font-size:12.5px; }
  pre { white-space: pre-wrap; font-size:12px; color:#2B8A3E; margin:8px 0 0; }
  .login { max-width: 380px; margin: 12vh auto 0; background:#fff; border-radius: 20px; padding: 26px; }
  .login h1 { font-size: 19px; }
  .login input { width:100%; margin:14px 0 10px; padding: 13px 14px; font-size: 20px; letter-spacing: 6px;
    text-align:center; border:1px solid #E9EBF2; border-radius: 12px; font-family: inherit; }
  .login .btn { width:100%; text-align:center; padding: 13px; }
  .err { color:#D6336C; font-size:12.5px; margin: 10px 0 0; }
  @media print {
    body { background:#fff; }
    .nav, .actions, .foot, input[type=file], #up, #msg { display:none !important; }
    .card, .stats div, tr { break-inside: avoid; }
    .wrap { max-width: none; padding: 0; }
  }
</style></head>
<body><div class="wrap">$body</div>
<script>
  var rb = document.getElementById('reload');
  if (rb) rb.onclick = function(){ location.reload(); };
  var pb = document.getElementById('print');
  if (pb) pb.onclick = function(){ window.print(); };
  var auto = document.getElementById('auto');
  if (auto) {
    auto.checked = localStorage.getItem('autoRefresh') === '1';
    auto.onchange = function(){
      localStorage.setItem('autoRefresh', auto.checked ? '1' : '0');
      if (auto.checked) setTimeout(function(){ location.reload(); }, 1000);
    };
    if (auto.checked) setTimeout(function(){ location.reload(); }, 30000);
  }
  var up = document.getElementById('up');
  if (up) up.onclick = async function(){
    var f = document.getElementById('f').files[0];
    var msg = document.getElementById('msg');
    if (!f) { msg.textContent = '先选择一个 .json 备份文件'; return; }
    if (!confirm('会用这个备份覆盖手机上的全部数据，确定继续？')) return;
    msg.textContent = '正在上传…';
    try {
      var text = await f.text();
      var r = await fetch('/restore', { method:'POST',
        headers:{'Content-Type':'text/plain;charset=utf-8'}, body: text });
      msg.textContent = await r.text();
    } catch (e) { msg.textContent = '上传失败：' + e; }
  };
</script>
</body></html>
''';

  // ------------------------------------------------------------ CSV
  String _csvTasks(AppState s) {
    final rows = <List<String>>[
      ['标题', '类型', '状态', '开始', '截止', '评分', '评价人', '评语', '总结'],
      for (final t in s.tasks)
        [
          t.title,
          t.type.label,
          t.done ? '已完成' : '未完成',
          t.startAt == null ? '' : fmtDateTime(t.startAt),
          t.dueAt == null ? '' : fmtDateTime(t.dueAt),
          t.score,
          t.reviewer,
          t.reviewNote,
          t.summary,
        ],
    ];
    return _csv(rows);
  }

  String _csvCourses(AppState s) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final list = [...s.courses]..sort((a, b) {
        final w = a.weekday.compareTo(b.weekday);
        return w != 0 ? w : a.startMin.compareTo(b.startMin);
      });
    final rows = <List<String>>[
      ['星期', '开始', '结束', '课程', '地点', '教师'],
      for (final c in list)
        [
          '周${names[(c.weekday - 1).clamp(0, 6)]}',
          hhmm(c.startMin),
          hhmm(c.endMin),
          c.name,
          c.location,
          c.teacher,
        ],
    ];
    return _csv(rows);
  }

  String _csvSummaries(AppState s) {
    final rows = <List<String>>[
      ['分类', '标题', '日期', '评分/结果', '总结'],
    ];
    for (final t in s.tasks.where((t) => t.hasSummary)) {
      rows.add([
        t.type.label,
        t.title,
        fmtDate(t.evaluatedAt ?? t.dueAt ?? t.createdAt),
        [t.score, t.reviewer].where((e) => e.isNotEmpty).join(' '),
        t.summary,
      ]);
    }
    for (final c in s.competitions.where((c) => c.summary.trim().isNotEmpty)) {
      rows.add([
        '比赛',
        c.name,
        fmtDate(c.resultAt ?? c.endAt ?? c.startAt ?? c.createdAt),
        compResultLabel(c.resultRank),
        c.summary,
      ]);
    }
    for (final n in s.notes.where((n) => n.hasReview)) {
      rows.add(['笔记', n.title, fmtDate(n.updatedAt), n.rating > 0 ? '${n.rating} 星' : '', n.review]);
    }
    for (final i in s.ideas.where((i) => i.hasReview)) {
      rows.add(['灵感', i.title, fmtDate(i.updatedAt), i.rating > 0 ? '${i.rating} 星' : '', i.review]);
    }
    return _csv(rows);
  }

  String _csvIdeas(AppState s) {
    final rows = <List<String>>[
      ['分类', '标题', '内容', '标签', '自评', '跟进', '更新时间'],
      for (final i in s.ideas)
        [
          i.kind.label,
          i.title,
          i.content,
          i.tags,
          i.rating > 0 ? '${i.rating} 星' : '',
          i.review,
          fmtDate(i.updatedAt),
        ],
    ];
    return _csv(rows);
  }

  String _csv(List<List<String>> rows) {
    final b = StringBuffer();
    for (final r in rows) {
      b.writeln(r.map(_csvCell).join(','));
    }
    return b.toString();
  }

  String _csvCell(String v) {
    final t = v.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    if (t.contains(',') || t.contains('"') || t.contains(';')) {
      return '"${t.replaceAll('"', '""')}"';
    }
    return t;
  }

  // ------------------------------------------------------------ 小工具
  Future<List<String>> _localIps() async {
    final scored = <MapEntry<int, String>>[];
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final ni in list) {
        final name = ni.name.toLowerCase();
        var base = 0;
        if (name.contains('wlan') || name.contains('ap') || name.contains('swlan') || name.contains('wifi')) {
          base += 20;
        }
        if (name.contains('rmnet') || name.contains('ccmni') || name.contains('pdp')) base -= 10;
        for (final a in ni.addresses) {
          final ip = a.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          var score = base;
          if (ip.startsWith('192.168.')) score += 8;
          if (ip.startsWith('10.')) score += 6;
          if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) score += 5;
          scored.add(MapEntry(score, ip));
        }
      }
    } catch (_) {}
    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.map((e) => e.value).toList();
  }

  String _stamp() {
    final n = DateTime.now();
    return '${n.year}${two(n.month)}${two(n.day)}';
  }

  String _mime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
      case 'md':
        return 'text/plain; charset=utf-8';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  void _attachment(HttpResponse res, String name) {
    final ascii = name.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', '');
    res.headers.set(
      'content-disposition',
      'attachment; filename="$ascii"; filename*=UTF-8\'\'${Uri.encodeComponent(name)}',
    );
  }

  String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  String _stars(int n) {
    if (n <= 0) return '';
    return '${List.filled(n, '★').join()}${List.filled(5 - n, '☆').join()} ';
  }

  String _hm(int seconds) {
    if (seconds < 60) return '0 分钟';
    final m = seconds ~/ 60;
    if (m < 60) return '$m 分钟';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h 小时' : '$h 小时 $r 分';
  }

  void _html(HttpResponse res, String html) {
    res.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    res.add(utf8.encode(html));
  }

  void _text(HttpResponse res, String text) {
    res.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
    res.add(utf8.encode(text));
  }

  String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
