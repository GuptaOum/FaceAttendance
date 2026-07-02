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

            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            if (uri == null) {
                Log.w(TAG, "no ringtone uri on device, using beep")
                beepFallback()
                return
            }
            Log.d(TAG, "using ringtone uri $uri")

            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            mp.setDataSource(applicationContext, uri)
            mp.setOnPreparedListener {
                it.start()
                Log.d(TAG, "ring playing")
            }
            mp.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaPlayer error what=$what extra=$extra, using beep")
                beepFallback()
                true
            }
            mp.prepareAsync()
            player = mp
        } catch (e: Exception) {
            Log.e(TAG, "playRing failed: $e, using beep")
            beepFallback()
        }
    }

    private fun beepFallback() {
        try {
            toneGen = ToneGenerator(AudioManager.STREAM_ALARM, 100)
            toneGen?.startTone(ToneGenerator.TONE_PROP_BEEP2, 1000)
            handler.postDelayed({ stopRing() }, 1200)
            Log.d(TAG, "beep fallback playing")
        } catch (e: Exception) {
            Log.e(TAG, "beep fallback failed: $e")
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
