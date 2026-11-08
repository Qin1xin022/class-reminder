package com.mystudy.class_reminder

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

private const val TAG = "BoardWidget"

/**
 * 小组件统一渲染框架：共用 layout/widget_text.xml，
 * 每个板块用自己的强调色（左侧竖条 + 标题色），内容由 WidgetData 现算。
 *
 * @param accent 强调色 ARGB
 * @param tab 点击后要打开的底部标签（0 今日 1 课表 2 任务 3 记录 4 比赛 5 通知 6 我的）
 */
abstract class BoardWidgetProvider(
    private val accent: Int,
    private val tab: Int,
) : HomeWidgetProvider() {

    abstract fun title(d: WidgetData): String
    abstract fun body(d: WidgetData): String

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        Log.d(TAG, "onUpdate ${this::class.simpleName} ids=${appWidgetIds.toList()} keys=${widgetData.all.keys}")
        val d = WidgetData.load(widgetData)
        Log.d(TAG, "data loaded hasData=${d.hasData} date=${d.dateText} taskCount=${d.taskCount}")
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra("tab", tab)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            1000 + tab,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val footer = if (d.updatedText.isEmpty()) {
            "打开 App 同步一次"
        } else {
            "数据 ${d.updatedText} · 点一下进 App"
        }
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_text)
            views.setTextViewText(R.id.widget_title, title(d))
            views.setTextViewText(R.id.widget_body, body(d))
            views.setTextViewText(R.id.widget_footer, footer)
            views.setTextColor(R.id.widget_title, accent)
            views.setInt(R.id.widget_accent, "setBackgroundColor", accent)
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
        Log.d(TAG, "onUpdate done ${this::class.simpleName} ids=${appWidgetIds.toList()}")
    }
}

/** 课程表：正在上 / 下一节 + 剩余时间，点开进「课表」 */
class CourseWidgetProvider : BoardWidgetProvider(0xFF4C6FFF.toInt(), 1) {
    override fun title(d: WidgetData) = "今日课程 · ${d.dateText}"

    override fun body(d: WidgetData): String {
        if (!d.hasData) return "打开 App 同步一次课表\n之后这里会自动更新"
        val cs = d.courses()
        if (cs.isEmpty()) return "今天没有课\n安排点自己的事吧"
        val now = WidgetData.nowMinutes()
        val b = StringBuilder()
        val cur = cs.firstOrNull { now >= it.start && now < it.end }
        if (cur != null) {
            b.append("正在上 ${WidgetData.hhmm(cur.start)}-${WidgetData.hhmm(cur.end)} ${cur.name}")
            if (cur.loc.isNotEmpty()) b.append(" @${cur.loc}")
            b.append("\n还剩 ${WidgetData.minutesText(cur.end - now)}\n")
        } else {
            val next = cs.firstOrNull { it.start > now }
            if (next != null) {
                b.append("下一节 ${WidgetData.hhmm(next.start)} ${next.name}")
                if (next.loc.isNotEmpty()) b.append(" @${next.loc}")
                b.append("\n距上课 ${WidgetData.minutesText(next.start - now)}\n")
            } else {
                b.append("今天的课上完了\n")
            }
        }
        for (c in cs) {
            if (c.end <= now) continue
            if (cur != null && c.start == cur.start) continue
            b.append("${WidgetData.hhmm(c.start)}-${WidgetData.hhmm(c.end)} ${c.name}")
            if (c.loc.isNotEmpty()) b.append(" @${c.loc}")
            b.append("\n")
        }
        return b.toString().trimEnd()
    }
}

/** 待办提醒：未完成清单 + 截止倒计时，点开进「任务」 */
class TaskWidgetProvider : BoardWidgetProvider(0xFFE8590C.toInt(), 2) {
    override fun title(d: WidgetData) =
        if (d.taskCount == 0) "待办提醒 · 全部完成" else "待办提醒 · ${d.taskCount} 项未完成"

    override fun body(d: WidgetData): String {
        if (!d.hasData) return "打开 App 同步一次待办"
        val ts = d.tasks()
        if (ts.isEmpty()) return "没有未完成的待办 🎉\n今天可以早点休息"
        val b = StringBuilder()
        for (t in ts) {
            val due = WidgetData.dueText(t.due)
            b.append("○ ${WidgetData.ellipsis(t.title, 13)}")
            if (due.isNotEmpty()) b.append(" · $due")
            b.append("\n")
        }
        if (d.taskCount > ts.size) b.append("还有 ${d.taskCount - ts.size} 项…")
        return b.toString().trimEnd()
    }
}

/** 今日概览：课程 + 待办 + 比赛 + 专注，点开进「今日」 */
class OverviewWidgetProvider : BoardWidgetProvider(0xFF7048E8.toInt(), 0) {
    override fun title(d: WidgetData) = "今日概览 · ${d.dateText}"

    override fun body(d: WidgetData): String {
        if (!d.hasData) return "打开 App 同步今天的安排"
        val cs = d.courses()
        val now = WidgetData.nowMinutes()
        val b = StringBuilder()
        b.append("今天 ${cs.size} 节课 · 待办 ${d.taskCount} 项\n")
        val cur = cs.firstOrNull { now >= it.start && now < it.end }
        val next = cs.firstOrNull { it.start > now }
        when {
            cur != null -> b.append("正在上 ${cur.name} · 还剩 ${WidgetData.minutesText(cur.end - now)}\n")
            next != null -> b.append(
                "下一节 ${WidgetData.hhmm(next.start)} ${next.name} · " +
                    "${WidgetData.minutesText(next.start - now)}后\n"
            )
            cs.isNotEmpty() -> b.append("今天的课上完了\n")
        }
        val c0 = d.comps().firstOrNull()
        if (c0 != null && c0.at != null) {
            b.append("比赛 ${WidgetData.ellipsis(c0.name, 10)} · ${WidgetData.countdownText(c0.at)}\n")
        }
        b.append("今日专注 ${WidgetData.hm(d.focusToday)}")
        return b.toString()
    }
}

/** 比赛提醒：待参加的比赛与倒计时；没有时显示战绩，点开进「比赛」 */
class CompWidgetProvider : BoardWidgetProvider(0xFFC77D00.toInt(), 4) {
    override fun title(d: WidgetData): String {
        val cs = d.comps()
        return if (cs.isNotEmpty()) "比赛提醒 · ${cs.size} 场待参加" else "比赛战绩"
    }

    override fun body(d: WidgetData): String {
        if (!d.hasData) return "打开 App 同步比赛信息"
        val cs = d.comps()
        if (cs.isEmpty()) {
            return if (d.pastComp == 0) {
                "还没有记录比赛\n去「比赛」里加一场"
            } else {
                "参加过 ${d.pastComp} 场 · 获奖 ${d.awarded} 场"
            }
        }
        val b = StringBuilder()
        for (c in cs) {
            b.append("· ${WidgetData.ellipsis(c.name, 11)}（${c.stage}）")
            val cd = WidgetData.countdownText(c.at)
            if (cd.isNotEmpty()) b.append(" · $cd")
            b.append("\n")
        }
        if (d.pastComp > 0) b.append("参加过 ${d.pastComp} 场 · 获奖 ${d.awarded} 场")
        return b.toString().trimEnd()
    }
}

/** 灵感记录：最近几条灵感/痛点/想法，点开进「记录」 */
class IdeaWidgetProvider : BoardWidgetProvider(0xFF6E56CF.toInt(), 3) {
    override fun title(d: WidgetData) = "灵感记录 · 共 ${d.ideaCount} 条"

    override fun body(d: WidgetData): String {
        if (!d.hasData) return "打开 App 同步灵感库"
        val is_ = d.ideas()
        if (is_.isEmpty()) return "还没有记录\n去「记录 → 灵感」随手写一条"
        val b = StringBuilder()
        for (i in is_) {
            b.append("· [${i.kind}] ${WidgetData.ellipsis(i.title, 12)}\n")
        }
        return b.toString().trimEnd()
    }
}

/** 专注统计：今日 / 本周时长，点开进「今日」看计时 */
class FocusWidgetProvider : BoardWidgetProvider(0xFF2B8A3E.toInt(), 0) {
    override fun title(d: WidgetData) = "专注统计 · 今日 ${WidgetData.hm(d.focusToday)}"

    override fun body(d: WidgetData): String {
        if (!d.hasData) return "打开 App 开始一次专注"
        val b = StringBuilder()
        if (d.focusRunning.isNotEmpty()) b.append("正在进行：${d.focusRunning}\n")
        b.append("今日 ${WidgetData.hm(d.focusToday)}\n")
        b.append("本周 ${WidgetData.hm(d.focusWeek)}")
        return b.toString()
    }
}
