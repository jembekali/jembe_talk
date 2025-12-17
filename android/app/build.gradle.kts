import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Loading ya Key Properties (Imeze neza)
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.example.jembe_talk"

    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
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
        applicationId = "com.example.jembe_talk"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = 1
        versionName = "1.0"
        
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            
            // >>>>> IBI NI BYO BIKEMURA IKIBAZO CYA "MissingPluginException" BURUNDU <<<<<
            // Ibi bibwira Android ngo "Ntugasibe code ucyeka ko idakenewe"
            isMinifyEnabled = false
            isShrinkResources = false
            
            lint.checkReleaseBuilds = false
            lint.abortOnError = false
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.8.20")
    implementation("androidx.multidex:multidex:2.0.1")
}

flutter {
    source = "../.."
}