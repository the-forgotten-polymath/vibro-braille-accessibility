package com.vibrobraille.haptics

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.os.Build

class MotorCalibrator(private val context: Context) {
    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    } else {
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    /**
     * Runs a perceptibility test.
     * Starts with a very low vibration and increases until the user signals they feel it.
     * This is a simplified version; in a real app, this would be an iterative process with UI feedback.
     */
    fun testPerceptibility(amplitude: Int): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = VibrationEffect.createOneShot(200, amplitude.coerceIn(0, 255))
            vibrator.vibrate(effect)
            return true
        }
        return false
    }

    /**
     * Normalizes the amplitude based on the detected threshold.
     */
    fun getNormalizedScale(threshold: Int): Float {
        // High threshold (weak motor) -> Scale up
        // Low threshold (strong motor) -> Scale down or keep same
        // Target: normalize so that threshold feels like 50/255
        val targetThreshold = 50.0f
        return targetThreshold / threshold.toFloat()
    }
}
