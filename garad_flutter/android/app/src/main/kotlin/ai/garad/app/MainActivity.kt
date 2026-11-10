package ai.garad.app

import android.content.Context
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Streams the speech recognizer's start/stop beeps play on (which one depends on the phone).
    private val beepStreams = intArrayOf(
        AudioManager.STREAM_MUSIC,
        AudioManager.STREAM_NOTIFICATION,
        AudioManager.STREAM_SYSTEM,
    )

    private val audio get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // Which streams this app muted, saved so a crash or a closed app can't leave the phone silent.
    private val prefs get() = getSharedPreferences("garad_call_audio", Context.MODE_PRIVATE)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        restore() // left muted by a call that never finished
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai.garad.app/call_audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "quiet" -> { quiet(); result.success(null) }
                    "restore" -> { restore(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    // Leaving the app mid-call gives the phone its sound back; the next listen quiets it again.
    override fun onPause() {
        restore()
        super.onPause()
    }

    override fun onDestroy() {
        restore()
        super.onDestroy()
    }

    /// Mutes the beep streams that are not muted already (never touches the user's own mutes).
    private fun quiet() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val muted = prefs.getStringSet("muted", emptySet())!!.toMutableSet()
        for (stream in beepStreams) {
            if (muted.contains(stream.toString()) || audio.isStreamMute(stream)) continue
            try {
                audio.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, 0)
                muted.add(stream.toString())
            } catch (_: SecurityException) {
                // Do Not Disturb forbids changing this stream: leave it.
            }
        }
        prefs.edit().putStringSet("muted", muted).apply()
    }

    /// Unmutes only what [quiet] muted.
    private fun restore() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val muted = prefs.getStringSet("muted", emptySet())!!
        if (muted.isEmpty()) return
        for (stream in muted) {
            try {
                audio.adjustStreamVolume(stream.toInt(), AudioManager.ADJUST_UNMUTE, 0)
            } catch (_: Exception) {
                // Nothing more to do for this stream.
            }
        }
        prefs.edit().remove("muted").apply()
    }
}
