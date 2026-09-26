package com.jkbmsr.pro

import android.content.Context
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
