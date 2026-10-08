package com.jkbmsr.pro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.os.UserManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Must extend FlutterFragmentActivity, not FlutterActivity. The local_auth
// plugin (biometric unlock) attaches a BiometricPrompt to the host
// FragmentActivity; against a plain FlutterActivity it cannot obtain an
// androidx Fragment and the prompt fails, which the app surfaces as a failed
// unlock and signs the user out. The BLE app has the same requirement.
class MainActivity : FlutterFragmentActivity() {
    private val securityChannel = "jkbmsr/security"

    companion object {
        // Must equal the manifest's default_notification_channel_id.
        private const val ALERT_CHANNEL_ID = "jkbmsr_alerts"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertChannel()
    }

    // FCM posts with the channel named by the manifest's
    // `com.google.firebase.messaging.default_notification_channel_id`
    // ("jkbmsr_alerts"). If that channel does not exist, FCM falls back to its
    // own "Miscellaneous" channel at default importance — so alerts arrive
    // without a heads-up and under a name the user can't recognise. Creating
    // it here at HIGH importance is what makes critical alerts actually
    // interrupt. The id MUST stay equal to the manifest value.
    private fun createAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(ALERT_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            ALERT_CHANNEL_ID,
            "Battery & gateway alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Critical battery conditions and gateway offline alerts"
        }
        manager.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "isClonedProfile") {
                    result.success(isRunningInClonedProfile())
                } else {
                    result.notImplemented()
                }
            }
    }

    // OEM "Dual Apps" / "Clone Apps" / "App Twin" features (Xiaomi, Samsung,
    // OnePlus, etc.) don't install a second, independent copy of the app —
    // they run this same install a second time inside a second Android user
    // profile. The real, primary install always runs as user serial 0; any
    // other serial means this process is the cloned copy.
    private fun isRunningInClonedProfile(): Boolean {
        val userManager = getSystemService(Context.USER_SERVICE) as? UserManager ?: return false
        val serial = userManager.getSerialNumberForUser(Process.myUserHandle())
        return serial != 0L
    }
}
