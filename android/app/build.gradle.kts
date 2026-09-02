plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase Cloud Messaging (HTTP v1): the google-services plugin is engaged
// only when android/app/google-services.json exists, so builds keep working
// before Firebase setup and use FCM after the file is added.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.softcar.passengersss"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications (java.time / desugaring).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
        }
    }

    defaultConfig {
        applicationId = "com.softcar.passengersss"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val propsFile = file("../key.properties")
            if (propsFile.exists()) {
                val props = mutableMapOf<String, String>()
                propsFile.readLines().forEach { line ->
                    val idx = line.indexOf('=')
                    if (idx > 0) {
                        props[line.substring(0, idx).trim()] = line.substring(idx + 1).trim()
                    }
                }
                storeFile = file(props["storeFile"] ?: "keystore/release.jks")
                storePassword = props["storePassword"]
                keyAlias = props["keyAlias"]
                keyPassword = props["keyPassword"]
            }
        }
    }

    buildTypes {
        release {
            isCrunchPngs = false
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
