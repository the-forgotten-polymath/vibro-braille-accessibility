package com.vibrobraille.vibrobraille_hybrid

import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.vibrobraille.haptics.HapticBridge
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Base64
import java.util.concurrent.atomic.AtomicBoolean
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity: FlutterActivity() {
    private val HAPTIC_CHANNEL = "com.vibrobraille/haptics"
    private val TRIGGER_CHANNEL = "com.vibrobraille/trigger"
    private val MIC_CHANNEL = "com.vibrobraille/mic"
    private val RECORD_AUDIO_PERMISSION_CODE = 200
    
    private var lastVolumeUpTime: Long = 0
    private var secondLastVolumeUpTime: Long = 0
    private val CLICK_INTERVAL = 400L // ms for double/triple click detection

    private var triggerChannel: MethodChannel? = null
    private var micChannel: MethodChannel? = null
    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null

    private fun checkAndRequestAudioPermission(): Boolean {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), RECORD_AUDIO_PERMISSION_CODE)
            return false
        }
        return true
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val hapticBridge = HapticBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HAPTIC_CHANNEL).setMethodCallHandler(hapticBridge)

        triggerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRIGGER_CHANNEL)

        micChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MIC_CHANNEL)
        micChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    startAudioRecording()
                    result.success(null)
                }
                "stopRecording" -> {
                    stopAudioRecording()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Request permission on app startup so it is ready
        checkAndRequestAudioPermission()
    }

    private fun startAudioRecording() {
        if (!checkAndRequestAudioPermission()) {
            System.err.println("Cannot start recording: RECORD_AUDIO permission not granted.")
            return
        }
        if (isRecording.get()) return
        
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        
        val chunkSize = 3200
        val readBufferSize = if (bufferSize > chunkSize) bufferSize else chunkSize
        
        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                readBufferSize
            )
            
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                System.err.println("AudioRecord initialization failed")
                return
            }
            
            audioRecord?.startRecording()
            isRecording.set(true)
            
            recordingThread = Thread({
                val buffer = ByteArray(chunkSize)
                while (isRecording.get()) {
                    val readBytes = audioRecord?.read(buffer, 0, chunkSize) ?: 0
                    if (readBytes > 0) {
                        val base64Data = Base64.encodeToString(buffer, 0, readBytes, Base64.NO_WRAP)
                        runOnUiThread {
                            micChannel?.invokeMethod("audioChunk", base64Data)
                        }
                    }
                }
            }, "VibroBraille-Mic-Thread")
            recordingThread?.start()
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    private fun stopAudioRecording() {
        isRecording.set(false)
        try {
            recordingThread?.join(1000)
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
        recordingThread = null
        
        try {
            if (audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                audioRecord?.stop()
            }
            audioRecord?.release()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        audioRecord = null
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val currentTime = System.currentTimeMillis()
        
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            if (currentTime - lastVolumeUpTime < CLICK_INTERVAL) {
                if (currentTime - secondLastVolumeUpTime < CLICK_INTERVAL * 2) {
                    // Triple press detected -> Emergency Stop
                    triggerChannel?.invokeMethod("emergencyStop", null)
                    lastVolumeUpTime = 0
                    secondLastVolumeUpTime = 0
                    return true
                }
                // Double press detected -> Toggle Live Mode
                triggerChannel?.invokeMethod("toggleLiveMode", null)
                lastVolumeUpTime = 0 // Reset
                secondLastVolumeUpTime = 0
                return true
            }
            secondLastVolumeUpTime = lastVolumeUpTime
            lastVolumeUpTime = currentTime
            return true // Consume to prevent native system volume bar HUD
        }

        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyLongPress(keyCode: Int, event: KeyEvent?): Boolean {
        return super.onKeyLongPress(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        return super.onKeyUp(keyCode, event)
    }
}
