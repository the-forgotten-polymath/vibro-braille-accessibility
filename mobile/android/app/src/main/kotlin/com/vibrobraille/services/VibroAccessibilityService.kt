package com.vibrobraille.services

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.util.Log

class VibroAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Capture focused text or text changes
        val text = when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_FOCUSED -> event.text.joinToString(" ")
            AccessibilityEvent.TYPE_VIEW_CLICKED -> event.text.joinToString(" ")
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> event.text.joinToString(" ")
            else -> null
        }

        if (!text.isNullOrBlank()) {
            Log.d("VibroBraille", "Captured text: $text")
            // Send this to the Braille Engine via a broadcast or direct call if bound
            // In a production setup, we'd use a LocalBroadcastManager or a shared Foreground Service
        }
    }

    override fun onInterrupt() {
        Log.d("VibroBraille", "Accessibility Service Interrupted")
    }

    override fun onServiceConnected() {
        Log.d("VibroBraille", "Accessibility Service Connected")
    }
}
