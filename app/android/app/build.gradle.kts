plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.archiekuo.stock_screener"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.archiekuo.stock_screener"
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

    // 固定的簽章金鑰：讓每次 GitHub Actions 編出來的 APK 都用「同一把鑰匙」簽名，
    // 這樣新版 apk 才能直接蓋掉舊版安裝、保留資料，不用每次都先移除舊版重裝。
    // 如果每次編譯用不同的鑰匙，Android 會認為是不同的 App，逼你先移除舊版才能
    // 裝新版，資料就會被清掉。
    //
    // 金鑰檔本身不放進 repo，是透過 GitHub Actions 的 Secrets 在編譯時解碼出來
    // （見 .github/workflows/build.yml 和 gen-android-keystore.yml，以及 README 的說明）。
    // 這裡在本機（或還沒設定 Secrets 時）找不到金鑰檔，就自動退回用 debug 金鑰簽，
    // 不會讓建置失敗。
    val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
    val hasReleaseKeystore = releaseKeystorePath != null && file(releaseKeystorePath).exists()
    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKeystore) "release" else "debug")
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
