# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Kotlin metadata (Firebase, etc.)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Gson — 플러그인이 예약 알림 JSON 캐시를 읽을 때 TypeToken 사용; R8이 제거하면
# loadScheduledNotifications → Missing type parameter (릴리즈에서 화면이 안 뜨는 것처럼 보일 수 있음)
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Home Widget – app provider must not be obfuscated (referenced in AndroidManifest)
-keep class com.bokkyun.teamsync.TeamSyncWidgetProvider { *; }
-keep class com.bokkyun.teamsync.TeamSyncWidgetActionReceiver { *; }
-keep class es.antonborri.home_widget.** { *; }

# OkHttp / Supabase HTTP layer
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Supabase / Realtime WebSocket
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

# Timezone (pure Dart, but suppress warnings)
-dontwarn sun.util.calendar.**

# Flutter Play Store 동적 배포 (미사용 기능 – missing class 경고 제거)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
