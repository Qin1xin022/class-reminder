package com.mystudy.class_reminder

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

data class WCourse(val start: Int, val end: Int, val name: String, val loc: String)
data class WTask(val title: String, val due: Long?)
data class WComp(val name: String, val at: Long?, val stage: String)
data class WIdea(val kind: String, val title: String)

/**
 * 小组件数据：Flutter 侧把结构化 JSON 写进 SharedPreferences（key = widget_json），
 * 这里解析后现场计算「正在上哪节课 / 下一节还有多久 / 待办还剩多少时间」，
 * 所以即使不打开 App，系统每次刷新小组件时内容也是新的。
 */
class WidgetData private constructor(private val json: JSONObject?) {

    val hasData: Boolean get() = json != null

    val dateText: String
        get() {
            val d = json?.optString("date").orEmpty()
            val w = json?.optString("weekday").orEmpty()
            if (d.isEmpty()) return "今天"
            return if (w.isEmpty()) d else "$d $w"
        }

    val updatedText: String
        get() {
            val ms = json?.optLong("updated") ?: 0L
            if (ms <= 0L) return ""
            val c = Calendar.getInstance().apply { timeInMillis = ms }
            return String.format(
                Locale.US,
                "%02d:%02d",
                c.get(Calendar.HOUR_OF_DAY),
                c.get(Calendar.MINUTE),
            )
        }

    val taskCount: Int get() = json?.optInt("taskCount") ?: 0
    val ideaCount: Int get() = json?.optInt("ideaCount") ?: 0
    val focusToday: Int get() = json?.optInt("focusToday") ?: 0
    val focusWeek: Int get() = json?.optInt("focusWeek") ?: 0
    val focusRunning: String
        get() {
            val j = json ?: return ""
            if (j.isNull("focusRunning")) return ""
            val v = j.optString("focusRunning")
            return if (v == "null") "" else v
        }
    val pastComp: Int get() = json?.optInt("pastComp") ?: 0
    val awarded: Int get() = json?.optInt("awarded") ?: 0

    fun courses(): List<WCourse> {
        val a = json?.optJSONArray("courses") ?: return emptyList()
        return (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            WCourse(
                start = o.optInt("s"),
                end = o.optInt("e"),
                name = o.optString("n"),
                loc = o.optString("l"),
            )
        }.sortedBy { it.start }
    }

    fun tasks(): List<WTask> {
        val a = json?.optJSONArray("tasks") ?: return emptyList()
        return (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            WTask(
                title = o.optString("t"),
                due = if (o.isNull("d")) null else o.optLong("d"),
            )
        }
    }

    fun comps(): List<WComp> {
        val a = json?.optJSONArray("comps") ?: return emptyList()
        return (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            WComp(
                name = o.optString("n"),
                at = if (o.isNull("a")) null else o.optLong("a"),
                stage = o.optString("s"),
            )
        }
    }

    fun ideas(): List<WIdea> {
        val a = json?.optJSONArray("ideas") ?: return emptyList()
        return (0 until a.length()).mapNotNull { i ->
            val o = a.optJSONObject(i) ?: return@mapNotNull null
            WIdea(kind = o.optString("k"), title = o.optString("t"))
        }
    }

    companion object {
        fun load(prefs: SharedPreferences): WidgetData {
            val raw = prefs.getString("widget_json", null)
            val obj = try {
                if (raw.isNullOrBlank()) null else JSONObject(raw)
            } catch (e: Exception) {
                null
            }
            return WidgetData(obj)
        }

        /** 现在几点几分（从 00:00 起算的分钟数） */
        fun nowMinutes(): Int {
            val c = Calendar.getInstance()
            return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        }

        fun hhmm(minutes: Int): String =
            String.format(Locale.US, "%02d:%02d", minutes / 60, minutes % 60)

        /** 时长（秒）→ 「1 小时 20 分」 */
        fun hm(seconds: Int): String {
            if (seconds < 60) return "0 分钟"
            val m = seconds / 60
            if (m < 60) return "$m 分钟"
            val h = m / 60
            val r = m % 60
            return if (r == 0) "$h 小时" else "$h 小时 $r 分"
        }

        /** 剩余分钟数 → 「23 分钟」/「1 小时 12 分」 */
        fun minutesText(min: Int): String {
            if (min <= 0) return "不到 1 分钟"
            if (min < 60) return "$min 分钟"
            val h = min / 60
            val r = min % 60
            return if (r == 0) "$h 小时" else "$h 小时 $r 分"
        }

        /** 截止时间 → 「今天 18:00」「明天 09:00」「10/31 12:00」「已逾期」 */
        fun dueText(ms: Long?): String {
            if (ms == null) return ""
            val now = Calendar.getInstance()
            val t = Calendar.getInstance().apply { timeInMillis = ms }
            val hm = String.format(
                Locale.US,
                "%02d:%02d",
                t.get(Calendar.HOUR_OF_DAY),
                t.get(Calendar.MINUTE),
            )
            val sameYear = now.get(Calendar.YEAR) == t.get(Calendar.YEAR)
            val diff = t.get(Calendar.DAY_OF_YEAR) - now.get(Calendar.DAY_OF_YEAR)
            val overdue = ms < System.currentTimeMillis()
            return when {
                overdue -> "已逾期"
                sameYear && diff == 0 -> "今天 $hm"
                sameYear && diff == 1 -> "明天 $hm"
                sameYear && diff == 2 -> "后天 $hm"
                else -> "${t.get(Calendar.MONTH) + 1}/${t.get(Calendar.DAY_OF_MONTH)} $hm"
            }
        }

        /** 距离某个时间点 → 「23 分钟后」「3 小时后」「5 天后」「已开始」 */
        fun countdownText(ms: Long?): String {
            if (ms == null) return ""
            val diff = ms - System.currentTimeMillis()
            if (diff <= 0) return "已开始"
            val min = (diff / 60000).toInt()
            if (min < 1) return "不到 1 分钟"
            if (min < 60) return "$min 分钟后"
            val h = min / 60
            if (h < 24) return "$h 小时后"
            return "${h / 24} 天后"
        }

        fun ellipsis(text: String, max: Int): String {
            val t = text.replace("\n", " ").trim()
            return if (t.length <= max) t else t.substring(0, max) + "…"
        }
    }
}
