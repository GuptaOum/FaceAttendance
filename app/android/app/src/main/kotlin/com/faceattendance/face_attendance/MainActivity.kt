package com.faceattendance.face_attendance

import android.media.Ringtone
import android.media.RingtoneManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "face_attendance/sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playRing" -> {
                        ringtone?.stop()
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        ringtone = RingtoneManager.getRingtone(applicationContext, uri)
                        ringtone?.play()
                        result.success(null)
                    }
                    "stopRing" -> {
                        ringtone?.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
