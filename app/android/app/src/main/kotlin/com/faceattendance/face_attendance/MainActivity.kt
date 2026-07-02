package com.faceattendance.face_attendance

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val TAG = "FaceSound"

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private var toneGen: ToneGenerator? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "face_attendance/sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playRing" -> {
                        Log.d(TAG, "playRing invoked from Dart")
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
        stopRing()
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            try {
                val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                val cur = am.getStreamVolume(AudioManager.STREAM_ALARM)
                Log.d(TAG, "alarm volume $cur/$maxVol, ringer mode ${am.ringerMode}")
                if (cur < maxVol / 2) {
                    am.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)
                }
            } catch (e: Exception) {
                Log.w(TAG, "volume adjust failed: $e")
            }
            toneGen = ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
            toneGen?.startTone(ToneGenerator.TONE_CDMA_ABBR_ALERT, 900)
            handler.postDelayed({ stopRing() }, 1100)
            Log.d(TAG, "confirmation beep playing")
        } catch (e: Exception) {
            Log.e(TAG, "playRing failed: $e")
        }
    }

    private fun stopRing() {
        try {
            player?.stop()
            player?.release()
        } catch (_: Exception) {
        }
        player = null
        try {
            toneGen?.release()
        } catch (_: Exception) {
        }
        toneGen = null
    }
}
