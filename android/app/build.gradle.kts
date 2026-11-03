plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.boddy.boddygame"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time, which does not exist below
        // API 26 — without desugaring the Android build fails outright (user
        // 2026-07-30, when the reminders were added).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.boddy.boddygame"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// CRASH REPORTING (Firebase Crashlytics). Both plugins need the
// google-services.json of the Firebase project the crashes should land in. It is
// not in the repo: download it from the Firebase console (Project settings ▸
// Your apps ▸ Android, package com.boddy.boddygame) into android/app/. Until it
// is there the plugins stay off and the app builds and runs as it always did —
// main.dart then simply finds no Firebase and keeps its normal error handling.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}

flutter {
    source = "../.."
}

dependencies {
    // The backport java.time is desugared onto. Required by
    // flutter_local_notifications; nothing else in the app needs it.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
