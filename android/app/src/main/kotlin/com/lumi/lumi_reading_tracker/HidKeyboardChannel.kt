package com.lumi.lumi_reading_tracker

import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.view.InputDevice
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Best-effort detection of external HID keyboard-wedge scanners.
 *
 * Android versions below API 29 report unknown so the Flutter UI falls back to
 * its existing heuristic. Some scanners identify as KEYBOARD_TYPE_NON_ALPHABETIC;
 * if a commonly deployed model is missed, the type check can be relaxed to
 * KEYBOARD_TYPE_NONE without ever blocking actual scan input.
 */
class HidKeyboardChannel private constructor(context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    InputManager.InputDeviceListener {

    companion object {
        private const val METHOD_CHANNEL = "lumi/hid_keyboard"
        private const val EVENT_CHANNEL = "lumi/hid_keyboard/events"

        fun register(context: Context, flutterEngine: FlutterEngine) {
            val instance = HidKeyboardChannel(context.applicationContext)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                .setMethodCallHandler(instance)
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
                .setStreamHandler(instance)
        }
    }

    private val inputManager =
        context.getSystemService(Context.INPUT_SERVICE) as InputManager
    private var eventSink: EventChannel.EventSink? = null
    private var isListening = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "isKeyboardConnected") {
            result.notImplemented()
            return
        }
        result.success(connectedState())
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        if (!isListening) {
            inputManager.registerInputDeviceListener(this, null)
            isListening = true
        }
        emitCurrentState()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        if (isListening) {
            inputManager.unregisterInputDeviceListener(this)
            isListening = false
        }
    }

    override fun onInputDeviceAdded(deviceId: Int) = emitCurrentState()

    override fun onInputDeviceRemoved(deviceId: Int) = emitCurrentState()

    override fun onInputDeviceChanged(deviceId: Int) = emitCurrentState()

    private fun emitCurrentState() {
        connectedState()?.let { eventSink?.success(it) }
    }

    private fun connectedState(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return InputDevice.getDeviceIds().any { deviceId ->
            val device = InputDevice.getDevice(deviceId) ?: return@any false
            !device.isVirtual &&
                device.isExternal &&
                device.sources and InputDevice.SOURCE_KEYBOARD == InputDevice.SOURCE_KEYBOARD &&
                device.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC
        }
    }
}
