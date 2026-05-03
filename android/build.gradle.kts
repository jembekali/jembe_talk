buildscript {
    val kotlinVersion by extra("1.9.22") 
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0") 
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
        classpath("com.google.gms:google-services:4.4.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: org.gradle.api.file.Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: org.gradle.api.file.Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
    
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            // Tegeka plugins zose gukoresha SDK 35
            android.compileSdkVersion(35)
            android.buildToolsVersion("35.0.0")
            
            if (android.namespace == null) {
                android.namespace = project.group.toString()
            }
        }
    }

    // ==============================================================================
    // IKI NI CYO GIKEMURA IKIBAZO CYA GOOGLE SIGN IN NA INAPPWEBVIEW BURUNDU
    // BIHATA AMA-LIBRARIES YOSE GUKORESHA VERISIYO ZUMVIKANA (PEACE TREATY)
    // ==============================================================================
    configurations.all {
        resolutionStrategy.eachDependency {
            // 1. Gukosora ikosa rya Stylus Handwriting (Android 14 Crash Fix)
            // Twahinduye 1.10.1 tuyigira 1.13.1 kuko ariyo isabwa na Android 14
            if (requested.group == "androidx.core" && (requested.name == "core" || requested.name == "core-ktx")) {
                useVersion("1.13.1") 
            }
            // 2. Gukosora ikosa rya ComponentActivity (Byategaga Google Sign In na Webview)
            if (requested.group == "androidx.activity") {
                useVersion("1.8.0")
            }
            // 3. Gukosora ibibazo bya Fragment byaterwaga na version mismatch
            if (requested.group == "androidx.fragment") {
                useVersion("1.6.1")
            }
            // 4. Guhata Lifecycle kugira ngo bihure na Activity nshya
            if (requested.group == "androidx.lifecycle") {
                useVersion("2.6.1")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}