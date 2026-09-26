import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: keystore material lives only in android/key.properties
// (gitignored) or CI secrets, never in source control. Falls back to debug
// signing — with a build-time warning — so a release build still runs
// locally before that file exists.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigningConfig = keystorePropertiesFile.canRead()
val keystoreProperties = Properties()
if (hasReleaseSigningConfig) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    logger.warn(
        "WARNING: android/key.properties not found — release builds will be " +
            "signed with the debug key and are not suitable for distribution. " +
            "See the signing policy in the private operations repository.",
    )
}

android {
    namespace = "com.jkbmsr.ble"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.jkbmsr.ble"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Version driven by pubspec.yaml (4.15.0+18 etc.) — the single source
        // of truth, so a tagged release and the APK metadata always agree.
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
            // Uses the protected upload keystore once android/key.properties
            // exists (see the signing policy in the private operations repo). Debug signing is
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

flutter {
    source = "../.."
}