import java.util.Properties
import java.io.FileInputStream
import java.io.File

// Function to read properties from local.properties (standard Flutter utility)
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
    // IMPORTANT: Ensure your AndroidManifest.xml has NO 'package' attribute
    // and that 'applicationId' in defaultConfig matches this 'namespace'.
    namespace = "com.grademate.grademate" // Replace 'com.grademate.grademate' with your final unique ID
    
    val flutterVersionCode = getFlutterProperty("flutter.versionCode")
    val flutterVersionName = getFlutterProperty("flutter.versionName")

    compileSdk = 36 
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.grademate.grademate" // Replace 'com.grademate.grademate' with your final unique ID
        minSdk = 24 
        targetSdk = 36 
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
    
    signingConfigs {
        create("release") {
            // 🛑 DIRECT CREDENTIALS (Fixes property reading errors)
            // Path: Ensure this is the correct absolute path to your JKS file.
            // Double backslashes (\\) are used for robustness on Windows.
            storeFile = file("C:\\Users\\ganesh\\Documents\\GradeMateKeys\\my_release_key.jks") 
            
            // Passwords and Alias
            storePassword = "Coder@4262"
            keyAlias = "grademate_keys"
            keyPassword = "Coder@4262"
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // This applies the hardcoded signing config
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            isDebuggable = true
            signingConfig = signingConfigs.getByName("debug")
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