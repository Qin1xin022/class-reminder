plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mystudy.class_reminder"
    compileSdk = flutter.compileSdkVersion
    // ndkVersion = flutter.ndkVersion   // 本项目无原生 C/C++ 代码，不需要 NDK

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mystudy.class_reminder"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 云端打包（GitHub Actions）时通过环境变量 CI_KEYSTORE 指定证书文件，
    // 保证和本机 debug 证书完全一致；本机不设这个变量，走默认 debug 配置。
    val ciKeystorePath = System.getenv("CI_KEYSTORE")
    signingConfigs {
        if (ciKeystorePath != null && file(ciKeystorePath).exists()) {
            create("ci") {
                storeFile = file(ciKeystorePath)
                storePassword = System.getenv("CI_KEYSTORE_PASS") ?: "android"
                keyAlias = System.getenv("CI_KEY_ALIAS") ?: "androiddebugkey"
                keyPassword = System.getenv("CI_KEY_PASS") ?: "android"
            }
        }
    }

    buildTypes {
        release {
            // 有 ci 配置就用它，否则用本机 debug 证书（两者其实是同一份）
            signingConfig = signingConfigs.findByName("ci") ?: signingConfigs.getByName("debug")
            logger.lifecycle("release 使用的签名配置：${signingConfig?.name}")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // ML Kit 中文离线识别模型（插件只声明 compileOnly，需要 App 自己引入；
    // 只带中文脚本，识别完全在手机本地跑，不联网不上传）
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

// 锁定 WorkManager 到稳定版：
// 新版 work-runtime(2.10+) 配合 R8 混淆会在启动时报
// "Failed to create an instance of androidx.work.impl.WorkDatabase" 直接闪退。
configurations.all {
    resolutionStrategy {
        force("androidx.work:work-runtime:2.9.1")
        force("androidx.work:work-runtime-ktx:2.9.1")
    }
}
