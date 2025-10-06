import java.util.Properties
import java.io.FileInputStream
import java.io.File

fun getFlutterProperty(key: String): String? {
    val localProperties = Properties()
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        FileInputStream(localPropertiesFile).use { localProperties.load(it) }
    }
    return localProperties.getProperty(key)
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.grademate"
    
    val flutterVersionCode = getFlutterProperty("flutter.versionCode")
    val flutterVersionName = getFlutterProperty("flutter.versionName")

    compileSdkVersion(35)
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.example.grademate"
        minSdkVersion(23)
        targetSdkVersion(35)
        versionCode = flutterVersionCode?.toInt() ?: 1
        versionName = flutterVersionName ?: "1.0"
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }
    
    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
        }
        getByName("debug") {
            isDebuggable = true
        }
    }
}

flutter {
    source = file("../..").path
}

dependencies {
    implementation(fileTree("libs") { include("*.jar") })
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.7.10")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}