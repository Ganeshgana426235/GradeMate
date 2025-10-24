# This file is used to specify application-wide ProGuard/R8 rules for the release build.

# This prevents minification from removing classes required by Flutter, Firebase, and your Main Activity.

# --- RULES TO PREVENT RELEASE CRASH (ClassNotFoundException) ---

# Keep Flutter's core JNI classes

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.* { *; }
-keep class io.flutter.view.* { *; }
-keep class io.flutter.embedding.* { *; }

# Keep YOUR Main Activity class. R8 must not rename or remove this.

# Use your current unique package name: com.grademate.grademate

-keep class com.grademate.grademate.MainActivity { *; }
-keep class * implements org.apache.http.client.methods.AbortableHttpRequest { *; }

# ptional: Rules for Firebase/Google Play Services.

# This prevents ProGuard/R8 from warning/crashing if it can't resolve dynamic Firebase classes.

-dontwarn com.google.android.gms.**
-keepnames class com.google.firebase.** { *; }