plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.baitulmal.simziwahapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.baitulmal.simziwahapp"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Memory optimization untuk low-end devices
        manifestPlaceholders["largeHeap"] = "false"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        
        debug {
            isMinifyEnabled = false
        }
    }
    
    // Bundle configuration - disable minify untuk split-per-abi
    // (split APK sudah optimal tanpa minification)
    bundle {
        language {
            enableSplit = false
        }
    }
    
    // Remove unused resources
    packagingOptions {
        exclude("META-INF/**")
        exclude("com/google/**")
        exclude("kotlin/**")
    }
}

flutter {
    source = "../.."
}
