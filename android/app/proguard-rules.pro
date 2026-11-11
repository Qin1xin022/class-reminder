# WorkManager + Room 在 R8 下反射创建 WorkDatabase_Impl 会失败，
# 导致启动即闪退（Failed to create an instance of WorkDatabase）。
# 保留这些类不被混淆/删除：
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class **_Impl { *; }
-dontwarn androidx.work.**

# flutter_local_notifications 用 Gson 反序列化已排程的通知，
# R8 混淆后泛型签名丢失 → "Missing type parameter" 闪退。
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.google.gson.**


# ML Kit 文字识别：插件引用了日/韩/天城文脚本类，但 App 只引入中文模型，
# 这些分支永远不会执行，用 dontwarn 抑制 R8 报错即可。
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit 文字识别：R8 混淆会破坏其内部反射/工厂，运行时报
# NullPointerException (Object.getClass()' on a null object reference)。
# （本项目 release 已显式关闭 R8；这些规则留作将来重新开启混淆时的保险。）
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
