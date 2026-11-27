// SPDX-License-Identifier: GPL-3.0-or-later
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. `key.properties` is git-ignored. Without it a release
// build FAILS, so an APK signed with the public debug key can never be shipped
// by accident. CI (which has no secrets) and local experiments opt in to the
// debug key explicitly with `-Pconsolarr.allowDebugSigning=true`, or the
// `ORG_GRADLE_PROJECT_consolarr.allowDebugSigning=true` environment variable.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val allowDebugSigning =
    providers.gradleProperty("consolarr.allowDebugSigning").orNull == "true"
val keystoreProperties = Properties()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    // Placeholder application id; changeable (see README).
    namespace = "org.consolarr.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.consolarr.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // R8 code shrinking/obfuscation and resource shrinking.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Debug signing is only reachable with the explicit opt-in above
            // (the task-graph check refuses the build otherwise).
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseRequested =
        allTasks.any {
            it.name == "assembleRelease" ||
                it.name == "bundleRelease" ||
                it.name == "packageRelease"
        }
    if (releaseRequested && !hasReleaseKeystore && !allowDebugSigning) {
        throw GradleException(
            "Release build refused: key.properties is missing, so the APK would " +
                "be signed with the public debug key. Provide key.properties, or " +
                "pass -Pconsolarr.allowDebugSigning=true for a non-distributable " +
                "build (CI does this)."
        )
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
