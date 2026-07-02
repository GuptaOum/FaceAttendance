package com.faceattendance.face_attendance

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ringtone: Ringtone? = null
    private var toneGen: ToneGenerator? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "face_attendance/sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playRing" -> {
                        playRing()
                        result.success(null)
                    }
                    "stopRing" -> {
                        stopRing()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playRing() {
        try {
            stopRing()
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)

            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val rt = if (uri != null) RingtoneManager.getRingtone(applicationContext, uri) else null
            if (rt == null) {
                toneGen = ToneGenerator(AudioManager.STREAM_ALARM, 100)
                toneGen?.startTone(ToneGenerator.TONE_PROP_BEEP2, 1000)
                handler.postDelayed({ stopRing() }, 1200)
                return
            }
            rt.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringtone = rt
            rt.play()
        } catch (_: Exception) {
        }
    }

    private fun stopRing() {
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        }
        ringtone = null
        try {
            toneGen?.release()
        } catch (_: Exception) {
        }
        toneGen = null
    }
}
