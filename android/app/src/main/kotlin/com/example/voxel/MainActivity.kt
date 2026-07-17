package com.example.voxel

import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServicePlugin

class MainActivity: FlutterActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.example.voxel/back_navigation"
    private var methodChannel: MethodChannel? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        Log.d(TAG, "provideFlutterEngine called")
        val engine = AudioServicePlugin.getFlutterEngine(context)
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        Log.d(TAG, "MethodChannel initialized in provideFlutterEngine")
        return engine
    }

    override fun onBackPressed() {
        Log.d(TAG, "onBackPressed called")
        val channel = methodChannel
        if (channel != null) {
            Log.d(TAG, "Invoking onBackPressed on MethodChannel")
            channel.invokeMethod("onBackPressed", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val handled = result as? Boolean ?: false
                    Log.d(TAG, "MethodChannel success. Handled: $handled")
                    if (!handled) {
                        super@MainActivity.onBackPressed()
                    }
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "MethodChannel error: $errorCode - $errorMessage")
                    super@MainActivity.onBackPressed()
                }
                override fun notImplemented() {
                    Log.e(TAG, "MethodChannel onBackPressed not implemented")
                    super@MainActivity.onBackPressed()
                }
            })
        } else {
            Log.w(TAG, "MethodChannel was null, falling back to super.onBackPressed()")
            super.onBackPressed()
        }
    }
}
