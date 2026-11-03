plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signVoiceTargetAbis = providers.gradleProperty("target-platform")
    .orElse("android-arm,android-arm64,android-x64").get().split(",").map { target ->
        when (target.trim()) {
            "android-arm" -> "armeabi-v7a"
            "android-arm64" -> "arm64-v8a"
            "android-x64" -> "x86_64"
            else -> error("Unsupported Android target: $target")
        }
    }
val signVoiceSplitPerAbi = providers.gradleProperty("split-per-abi").orElse("false").get().toBoolean()

android {
    buildFeatures { resValues = true }
    // Bundle exactly the same verified hand model as the web detector.
    sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("handModelAssets").get().asFile)
    namespace = "com.example.sign_voice"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        val appLinkHost = providers.gradleProperty("signVoiceAppLinkHost").orElse("localhost").get()
        manifestPlaceholders["signVoiceAppLinkHost"] = appLinkHost
        resValue("string", "signvoice_app_link_host", appLinkHost)
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.sign_voice"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // MediaPipe bundles several ABIs. Package only ABIs for which this
        // build also supplies Flutter's engine and AOT application library.
        if (!signVoiceSplitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(signVoiceTargetAbis)
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles("proguard-rules.pro")
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

val bundleHandModel by tasks.registering(Copy::class) {
    from("../../web/mediapipe/hand_landmarker.task")
    into(layout.buildDirectory.dir("handModelAssets"))
}
tasks.named("preBuild").configure { dependsOn(bundleHandModel) }

dependencies {
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.2.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.mediapipe:tasks-vision:0.10.32")
    testImplementation("junit:junit:4.13.2")
}
