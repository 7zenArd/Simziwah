# Flutter WebView wrapper optimization

# Keep Flutter native classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep InAppWebView classes
-keep class com.pichillilorenzo.** { *; }

# Keep permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep image picker
-keep class com.yalantis.ucrop.** { *; }
-keep class com.canhub.cropper.** { *; }

# Keep camera classes
-keep class com.google.android.cameraview.** { *; }

# Keep Google Play Core (optional, untuk dynamic features)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep XML Stream (optional dependency)
-dontwarn javax.xml.stream.**

# Keep Tika utils
-dontwarn org.apache.tika.**

# Keep JavaScriptInterface methods
-keepclasseswithmembernames class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Remove logging in release builds
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# Optimization
-optimizationpasses 5
-dontusemixedcaseclassnames

# Remove unused method parameters
-keepattributes Exceptions,InnerClasses,Signature,Deprecated,SourceFile,LineNumberTable,*Annotation*,EnclosingMethod

# WebView
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, ...);
}
-keepclassmembers class * extends android.webkit.WebChromeClient {
    public void *(android.webkit.WebView, ...);
}

# Preserve line numbers for debugging
-renamesourcefileattribute SourceFile
