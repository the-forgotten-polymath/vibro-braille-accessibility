package com.vibrobraille.services

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class VibroNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val packageName = sbn?.packageName
        val tickerText = sbn?.notification?.tickerText
        val extras = sbn?.notification?.extras
        val title = extras?.getString("android.title")
        val text = extras?.getCharSequence("android.text")

        Log.d("VibroBraille", "Notification from $packageName: $title - $text")
        
        // Push to Braille Engine
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        Log.d("VibroBraille", "Notification removed")
    }
}
