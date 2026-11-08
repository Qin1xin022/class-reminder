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

