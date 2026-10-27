# MediaPipe task graph options use protobuf-lite reflection. R8 must preserve
# generated message fields or release initialization fails (e.g. platform_).
# https://github.com/protocolbuffers/protobuf/blob/main/java/lite.md
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

# MediaPipe Graph initializes Flogger using its Java caller stack. Inlining
# FluentLogger.forEnclosingClass() removes that caller and aborts Graph startup.
-keep class com.google.common.flogger.** { *; }

# MediaPipe JNI looks up Java types/constructors by their original names,
# including MediaPipeException when a GPU is unsupported. Preserve that boundary
# so the GPU -> CPU fallback can return an exception instead of a JNI abort.
-keep class com.google.mediapipe.** { *; }

# tasks-vision omits these optional graph profiling/template protos. HandLandmarker
# uses neither API; keep the JNI boundary without requiring unused SDK modules.
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
