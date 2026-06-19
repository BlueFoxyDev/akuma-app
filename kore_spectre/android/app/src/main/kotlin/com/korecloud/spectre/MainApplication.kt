package com.korecloud.spectre

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        manager.createNotificationChannel(
            NotificationChannel(
                "korespectre_bg",
                "KoreSpectre Background",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Monitorando datacenter em background"
            }
        )

        manager.createNotificationChannel(
            NotificationChannel(
                "korespectre_alerts",
                "Alertas de Monitor",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Notificações de status do datacenter"
            }
        )
    }
}
