import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Declared (with a version) in settings.gradle.kts's root plugins block;
    // must actually be applied here too, or the kotlin { compilerOptions {} }
    // block below fails to resolve at all (caught by a real `flutter build`,
    // not by static analysis).
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase Cloud Messaging (docs/notification-plan.md) needs a real project
// config file added through the approved secrets process — see
// docs/AI_HANDOFF_MOBILE_MVP.md. Applying the plugin only when that file
// exists keeps the project buildable for everyone else in the meantime.
val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
    // NOTE: the Crashlytics Gradle plugin is intentionally not applied — its
    // component failed to register at runtime on this AGP 9 / R8 build, which
    // broke Firebase.initializeApp() (and therefore FCM). See lib/main.dart.
}

// Release signing: keystore material lives only in android/key.properties
// (gitignored; see key.properties.example) or CI secrets, never in source
// control. Falls back to debug signing — with a build-time warning — so a
// release build still runs locally before that file exists.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigningConfig = keystorePropertiesFile.canRead()
val keystoreProperties = Properties()
if (hasReleaseSigningConfig) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    logger.warn(
        "WARNING: android/key.properties not found — release builds will be " +
            "signed with the debug key and are not suitable for store distribution. " +
            "See android/key.properties.example.",
    )
}

// Google Play requires new apps/updates to target a recent API level (its
// policy currently requires Android 15 / API 35 at minimum, and Android 16 /
// API 36 once that becomes the enforced floor). We pin compileSdk/targetSdk
// to 36 explicitly rather than trusting flutter.compileSdkVersion /
// flutter.targetSdkVersion, since those track whatever Flutter SDK happens to
// be installed and could resolve lower on an older toolchain.
val playTargetSdk = 36

android {
    namespace = "com.jkbmsr.pro"
    compileSdk = playTargetSdk
    // Pinned above flutter.ndkVersion's default: firebase_core/_crashlytics/
    // _messaging, jni_flutter, package_info_plus, shared_preferences_android,
    // and url_launcher_android all require this NDK (they're backward
    // compatible, so the higher pin satisfies every plugin at once) — caught
    // by a real `flutter build`, not visible from Dart alone.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable package identity used by the Android application.
        applicationId = "com.jkbmsr.pro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = playTargetSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Uses the release keystore once android/key.properties
            // exists (see key.properties.example). Debug signing is
            // retained as a fallback only so local release-mode smoke tests
            // can run before that file is provisioned.
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
