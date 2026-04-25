package com.orbitskull.luming

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.util.Log

class MainActivity: AudioServiceActivity() {
    private val CHANNEL = "com.orbitskull.luming/audio_effects"
    private var noiseSuppressor: NoiseSuppressor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "applyNoiseSuppression") {
                val sessionId = call.argument<Int>("sessionId")
                if (sessionId != null) {
                    val success = applyNoiseSuppression(sessionId)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "Session ID is null", null)
                }
            } else if (call.method == "releaseNoiseSuppression") {
                releaseNoiseSuppressor()
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun applyNoiseSuppression(sessionId: Int): Boolean {
        return try {
            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor?.release()
                noiseSuppressor = NoiseSuppressor.create(sessionId)
                noiseSuppressor?.enabled = true
                Log.d("AudioEffects", "Noise suppression enabled for session $sessionId")
                true
            } else {
                Log.w("AudioEffects", "Noise suppression not available on this device")
                false
            }
        } catch (e: Exception) {
            Log.e("AudioEffects", "Error creating noise suppressor", e)
            false
        }
    }

    private fun releaseNoiseSuppressor() {
        noiseSuppressor?.release()
        noiseSuppressor = null
    }
}
