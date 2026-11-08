package com.mystudy.class_reminder

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面小组件点击后带着 tab 参数打开 App：
 * 冷启动时由 Flutter 主动取一次（getLaunchTab），
 * App 已在后台时走 onNewIntent → openTab 直接切标签。
 */
class MainActivity : FlutterActivity() {

    private var pendingTab: Int? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingTab = tabFrom(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "getLaunchTab") {
                    result.success(pendingTab)
                    pendingTab = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val tab = tabFrom(intent) ?: return
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("openTab", tab)
        } else {
            pendingTab = tab
        }
    }

    private fun tabFrom(intent: Intent?): Int? {
        val t = intent?.getIntExtra("tab", -1) ?: -1
        return if (t in 0..6) t else null
    }

    companion object {
        private const val CHANNEL = "class_reminder/launch"
    }
}
