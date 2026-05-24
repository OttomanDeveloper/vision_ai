# MediaPipe — uses stack-walking in Graph.<clinit> to find its native loader.
# R8 obfuscation renames the caller class, breaking the stack check.
-keep class com.google.mediapipe.** { *; }
-keepclassmembers class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# MediaPipe framework internals — Graph static initializer walks the call stack
-keep class com.google.mediapipe.framework.** { *; }

# Protobuf — MediaPipe serializes model configs via protobuf reflection
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Google ML Kit Face Detection — internal GMS classes use reflection
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face_bundled.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# TensorFlow Lite — native JNI bindings
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# GPU delegates loaded dynamically
-keep class com.google.mediapipe.tasks.core.jni.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# Preserve stack frame info for MediaPipe's stack-walking native loader
-keepattributes SourceFile,LineNumberTable
