# Project-specific R8/ProGuard rules for release builds. AGP 9's default
# release buildType enables minification and requires this file to exist
# (found by actually running `flutter build apk --release`, not visible from
# static Dart/Kotlin review — Flutter's own engine classes are already kept
# via consumer rules bundled in its AAR, so nothing Flutter-specific is
# needed here).

# Firebase Messaging/Crashlytics reference some Play Core split-install APIs
# reflectively for deferred components even when unused; keep R8 from failing
# on missing classes for those instead of suppressing warnings project-wide.
-dontwarn com.google.android.play.core.**
