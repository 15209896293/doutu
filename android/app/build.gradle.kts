import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取 --dart-define（Flutter 通过 -Pdart-defines 以 base64 逗号分隔传入）
val dartDefines = mutableMapOf<String, String>()
(project.findProperty("dart-defines") as String?)?.split(",")?.forEach { e ->
    if (e.isNotBlank()) {
        try {
            val decoded = String(Base64.getDecoder().decode(e), Charsets.UTF_8)
            val idx = decoded.indexOf('=')
            if (idx > 0) dartDefines[decoded.substring(0, idx)] = decoded.substring(idx + 1)
        } catch (_: IllegalArgumentException) { }
    }
}
val isTrialBuild = dartDefines["TRIAL_MODE"] == "true"

android {
    namespace = "com.doutu.doutu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 试用版用独立 applicationId（.trial），可与正式版共存安装
        applicationId = "com.doutu.doutu" + if (isTrialBuild) ".trial" else ""
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
        if (isTrialBuild) {
            manifestPlaceholders["appLabel"] = "豆图试用版"
        } else {
            manifestPlaceholders["appLabel"] = "豆图"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
