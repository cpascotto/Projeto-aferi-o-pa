-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# Preserve Flutter embedding classes used by plugins (e.g. path_provider)
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Preserve Flutter plugin registrar / embedding interfaces
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
