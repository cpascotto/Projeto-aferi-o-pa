plugins {
    id("com.android.application")
    id("com.chaquo.python")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_identification_mvp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_identification_mvp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        setProperty("archivesBaseName", "vincere")

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

chaquopy {
    defaultConfig {
        version = "3.8"
        buildPython("py", "-3.8")
        pip {
            install("numpy==1.19.5")
            install("protobuf==3.20.3")
            install("h5py==2.10.0")
            install("gast==0.2.2")
            install("Pillow==9.2.0")
            install("opencv-python==4.5.1.48")
            install("tensorflow==2.1.0")
            install("requests==2.32.4")
            install("tqdm==4.67.3")
            install("gdown==5.2.1")
        }
    }
}

dependencies {
}

flutter {
    source = "../.."
}
