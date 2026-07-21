package com.lumi.lumi_reading_tracker

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val BLUETOOTH_SETTINGS_CHANNEL = "lumi/bluetooth_settings"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HidKeyboardChannel.register(this, flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLUETOOTH_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "openBluetoothSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            // Android officially exposes a dedicated screen for pairing and
            // disconnecting Bluetooth devices. A small number of vendor ROMs
            // omit that activity, so fall back to wireless settings and then
            // the Settings home page without ever opening Lumi's app settings.
            val destinations = listOf(
                Intent(Settings.ACTION_BLUETOOTH_SETTINGS) to "bluetooth",
                Intent(Settings.ACTION_WIRELESS_SETTINGS) to "systemSettings",
                Intent(Settings.ACTION_SETTINGS) to "systemSettings",
            )
            val destination = destinations.firstOrNull { (intent, _) ->
                intent.resolveActivity(packageManager) != null
            }
            if (destination == null) {
                result.success("unavailable")
                return@setMethodCallHandler
            }

            try {
                startActivity(destination.first)
                result.success(destination.second)
            } catch (_: Exception) {
                result.success("unavailable")
            }
        }
    }
}
