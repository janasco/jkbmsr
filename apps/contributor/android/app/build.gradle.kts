import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Declared (with a version) in settings.gradle.kts's root plugins block;
    // must actually be applied here too, or the kotlin { compilerOptions {} }
    // block below fails to resolve at all.
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: keystore material lives only in android/key.properties
// (gitignored; see key.properties.example), never in source control. Falls
// back to debug signing — with a build-time warning — so a release build still
// runs locally before that file is provisioned, exactly as apps/pro does.
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

android {
    namespace = "com.jkbmsr.contributor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Same Java level as apps/pro (Java 17), so this app starts on the
        // modern toolchain Flutter recommends.
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jkbmsr.contributor"
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
            // Uses the release keystore once android/key.properties exists
            // (see key.properties.example). Debug signing is retained as a
            // fallback only so local release-mode smoke tests can run before
            // that file is provisioned.
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
