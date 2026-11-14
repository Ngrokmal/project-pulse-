plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.pulsemessenger.pulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Must match firebase/google-services.json (package_name).
        applicationId = "com.pulsemessenger.app"
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

    buildTypes {
        release {
            // PHASE 2 task: replace with a real upload keystore read from
            // android/key.properties (kept out of git). Debug signing today so
            // CI produces an installable artifact.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // AGP's lint task crashes inside its own JavaDocParser on this toolchain
    // (NoSuchMethodError), which fails `flutter build apk --release` for
    // reasons unrelated to our code. Dart static analysis (`flutter analyze`,
    // run as a separate CI gate) is our static-analysis of record, so release
    // lint is disabled here and tracked as a separate task instead of being
    // silently ignored during development.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
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
