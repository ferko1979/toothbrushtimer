package hu.fogmosas.shared

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

object Haptics {
    private fun vibrator(ctx: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31) ctx.getSystemService(VibratorManager::class.java)?.defaultVibrator
        else @Suppress("DEPRECATION") ctx.getSystemService(Vibrator::class.java)

    /** "tap" = quadrant change, "success" = goal reached. */
    fun play(ctx: Context, kind: String) {
        val v = vibrator(ctx) ?: return
        val effect = if (kind == "success") VibrationEffect.createWaveform(longArrayOf(0, 120, 80, 120, 80, 250), -1)
        else VibrationEffect.createOneShot(180, VibrationEffect.DEFAULT_AMPLITUDE)
        v.vibrate(effect)
    }

    fun warning(ctx: Context) {
        vibrator(ctx)?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 150, 400), -1))
    }
}
