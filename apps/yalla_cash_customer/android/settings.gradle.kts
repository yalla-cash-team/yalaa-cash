pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // LOCAL-ONLY fallback mirrors, tried before google(), for environments
        // where dl.google.com cannot be reached directly.
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    // Local-only workaround: the com.google.gms.google-services plugin marker
    // is unresolved from every repository above in this environment. Resolve
    // it directly to its known backing module instead.
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "com.google.gms.google-services") {
                useModule("com.google.gms:google-services:4.4.2")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Reads android/app/google-services.json at build time so firebase_core
    // can initialize without an explicit FirebaseOptions in Dart.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// The Flutter Gradle plugin adds its own storage.googleapis.com/download.flutter.io
// mirror to every project's repositories when it applies. Declaring google()/
// mavenCentral() here, centrally, ensures they are registered before that plugin
// runs and are tried for normal Android/Firebase dependency resolution instead of
// depending solely on that mirror being reachable.
dependencyResolutionManagement {
    repositories {
        // LOCAL-ONLY fallback mirror, tried before google(), for environments
        // where dl.google.com cannot be reached directly.
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        google()
        mavenCentral()
    }
}

include(":app")
