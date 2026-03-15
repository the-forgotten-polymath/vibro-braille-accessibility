package com.vibrobraille.haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class HapticBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    } else {
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    private var motorScale: Float = 1.0f

    fun setScale(scale: Float) {
        this.motorScale = scale
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "vibrateWaveform" -> {
                val timings = call.argument<List<Long>>("timings")
                val amplitudes = call.argument<List<Int>>("amplitudes")
                android.util.Log.d("VibroHaptics", "Received vibration request: Timings=$timings, Amplitudes=$amplitudes")
                
                if (timings != null && amplitudes != null) {
                    try {
                        playWaveform(timings.toLongArray(), amplitudes.toIntArray())
                        result.success(null)
                    } catch (e: Exception) {
                        android.util.Log.e("VibroHaptics", "Error playing waveform: ${e.message}")
                        // Emergency fallback: standard vibration
                        val totalDuration = timings.map { it }.sum()
                        vibrator.vibrate(totalDuration) 
                        result.success(null) 
                    }
                } else {
                    result.error("INVALID_ARGUMENTS", "Timings or amplitudes missing", null)
                }
            }
            "setMotorScale" -> {
                val scale = call.argument<Double>("scale")?.toFloat()
                if (scale != null) {
                    motorScale = scale
                    result.success(null)
                }
            }
            "cancel" -> {
                vibrator.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun playWaveform(timings: LongArray, amplitudes: IntArray) {
        // Stop any previous vibration to prevent overlap issues
        try {
            vibrator.cancel()
        } catch (e: Exception) {
            android.util.Log.e("VibroHaptics", "Error cancelling previous vibration: ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Apply motor scale to amplitudes
            val scaled = amplitudes.toMutableList().map { (it * motorScale).toInt().coerceIn(0, 255) }.toMutableList()
            val times = timings.toMutableList()

            // 🔥 CRITICAL FIX: Android requires first amplitude = 0 (initial delay)
            // But we must ensure arrays remain same size!
            // If we add to one, we must add to the other.
            if (scaled.isNotEmpty() && scaled[0] != 0) {
                 scaled.add(0, 0)
                 times.add(0, 10L) // Increase to 10ms to be safe
                 android.util.Log.d("VibroHaptics", "Added initial 10ms silence padding")
            }

            android.util.Log.d("VibroHaptics", "Waveform request received - executing vibration")
            android.util.Log.d("VibroHaptics", "Final timings (${times.size}): $times")
            android.util.Log.d("VibroHaptics", "Final amplitudes (${scaled.size}): $scaled")

            if (times.size != scaled.size) {
                android.util.Log.e("VibroHaptics", "MISMATCH: active timings=${times.size}, active amplitudes=${scaled.size}")
            }

            val effect = VibrationEffect.createWaveform(
                times.toLongArray(),
                scaled.toIntArray(),
                -1
            )

            vibrator.vibrate(effect)
        } else {
            // Fallback for older devices (only timings supported)
            vibrator.vibrate(timings, -1)
        }
    }
}
