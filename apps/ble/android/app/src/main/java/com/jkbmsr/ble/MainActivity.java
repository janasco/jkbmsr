package com.jkbmsr.ble;

import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import java.io.File;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.jkbmsr.ble/self_update";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("installApk".equals(call.method)) {
                        installApk(call.argument("path"), result);
                    } else if ("canInstall".equals(call.method)) {
                        result.success(hasInstallPermission());
                    } else {
                        result.notImplemented();
                    }
                });
    }

    private boolean hasInstallPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return getPackageManager().canRequestPackageInstalls();
        }
        return true;
    }

    /** Hands the downloaded APK to the system installer via FileProvider. */
    private void installApk(String path, MethodChannel.Result result) {
        try {
            File apk = new File(path);
            if (!apk.exists()) {
                result.error("not_found", "APK file missing", null);
                return;
            }
            Uri uri = FileProvider.getUriForFile(
                    this, getPackageName() + ".fileprovider", apk);
            Intent intent = new Intent(Intent.ACTION_INSTALL_PACKAGE)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                            | Intent.FLAG_ACTIVITY_NEW_TASK);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    && !hasInstallPermission()) {
                // Route through the exact settings page; the flag lands the
                // user back on the installer when they return.
                startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + getPackageName()))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                result.success(false);
                return;
            }
            startActivity(intent);
            result.success(true);
        } catch (Exception e) {
            result.error("install_failed", e.getMessage(), null);
        }
    }
}
