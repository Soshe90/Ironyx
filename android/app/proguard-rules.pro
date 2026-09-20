# Release shrinking rules. Flutter's own rules are applied by the Flutter Gradle
# plugin; this file covers the plugins that need more.

# flutter_local_notifications persists scheduled notifications as JSON through
# Gson and reads them back by reflection when the alarm fires (including after
# a reboot). Renamed or stripped fields make that round-trip fail silently, and
# a rename between two releases orphans notifications scheduled by the first.
# Rules follow the plugin's own example app and Gson's Android example.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
