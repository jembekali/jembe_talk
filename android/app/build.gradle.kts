import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.jembetalk.app"
    
    // 🚀 CompileSdk 35 bituma usoma amategeko mashya ya Android 15 (Itegeko rishya)
    compileSdk = 35 

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            if (keyPropertiesFile.exists()) {
                storeFile = rootProject.file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String 
            }
        }
    }

    defaultConfig {
        applicationId = "com.jembetalk.app"
        minSdk = 24
        
        // 🔥 TargetSdk 35 ni ryo tegeko Google Play yagusabaga (Fixed)
        targetSdk = 35 
        
        // 🚀 VersionCode 16 bituma isimbura verisiyo ya 15 yari ifite amakosa (Fixed)
        versionCode = 23
        versionName = "1.1.1"
        
        multiDexEnabled = true 
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            
            // Ibi tubireke kuri false niba bitari byarateganyijwe mbere
            isMinifyEnabled = false 
            isShrinkResources = false
            
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            
            lint.checkReleaseBuilds = false
            lint.abortOnError = false
        }
    }
}

dependencies {
    // 🚀 Inkingi zifasha App gukora neza (Compatibility)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.core:core-ktx:1.13.1")
    
    // 🔥 Firebase BOM ifite amavugurura agezweho
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging")

    // 🔥 Kurinda background crashes kuri Android 14/15
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    implementation("com.google.android.gms:play-services-base:18.4.0")
}

flutter {
    source = "../.."
}