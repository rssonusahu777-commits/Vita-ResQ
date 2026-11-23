package com.example.jan_sarthi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val NOTIFICATION_CHANNEL = "com.example.jan_sarthi/notifications"
    private val VOICE_CHANNEL = "com.example.jan_sarthi/voice"
    private val EMERGENCY_CHANNEL_ID = "vita_resq_emergency_alerts"
    private val EMERGENCY_VOICE_CHANNEL_ID = "vita_resq_voice_alerts"

    private var pendingEmergencyId: String? = null
    private var notificationChannel: MethodChannel? = null
    private var voiceChannel: MethodChannel? = null

    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null
    private var mediaPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createEmergencyNotificationChannels()
        handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLaunchIntent(intent)
    }

    private fun handleLaunchIntent(intent: Intent?) {
        val emergencyId = intent?.getStringExtra("emergencyId")
        if (!emergencyId.isNullOrEmpty()) {
            pendingEmergencyId = emergencyId
            notificationChannel?.invokeMethod("onNotificationTapped", emergencyId)
        }
    }

    private fun createEmergencyNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 1. Standard Emergency Alerts Channel (system default sound & vibration)
            val standardName = "Vita ResQ Emergency Alerts"
            val standardDesc = "High-importance civilian emergency and responder alerts"
            val standardImportance = NotificationManager.IMPORTANCE_HIGH
            val standardChannel = NotificationChannel(EMERGENCY_CHANNEL_ID, standardName, standardImportance).apply {
                description = standardDesc
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(standardChannel)

            // 2. Spoken Emergency Alerts Channel (packaged voice announcement)
            val voiceResId = resources.getIdentifier("emergency_alert_voice", "raw", packageName)
            if (voiceResId != 0) {
                val voiceName = "Vita ResQ Spoken Emergency Alerts"
                val voiceDesc = "High-importance emergency alerts with spoken voice announcements"
                val voiceImportance = NotificationManager.IMPORTANCE_HIGH
                val voiceChannel = NotificationChannel(EMERGENCY_VOICE_CHANNEL_ID, voiceName, voiceImportance).apply {
                    description = voiceDesc
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC

                    val soundUri = Uri.parse("android.resource://$packageName/$voiceResId")
                    val audioAttributes = AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .build()
                    setSound(soundUri, audioAttributes)
                }
                notificationManager.createNotificationChannel(voiceChannel)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Dedicated Emergency Notification Channel
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialEmergencyId" -> {
                        val id = pendingEmergencyId
                        pendingEmergencyId = null
                        result.success(id)
                    }
                    "showEmergencyNotification" -> {
                        val id = call.argument<Int>("id") ?: 1001
                        val title = call.argument<String>("title") ?: "Vita ResQ — Emergency Nearby"
                        val body = call.argument<String>("body") ?: "A nearby user needs assistance."
                        val emergencyId = call.argument<String>("emergencyId")
                        val useVoiceAlert = call.argument<Boolean>("useVoiceAlert") ?: true

                        showNativeEmergencyNotification(id, title, body, emergencyId, useVoiceAlert)
                        result.success(true)
                    }
                    "cancelEmergencyNotification" -> {
                        val id = call.argument<Int>("id") ?: 1001
                        val notificationManager = NotificationManagerCompat.from(this@MainActivity)
                        notificationManager.cancel(id)
                        result.success(true)
                    }
                    "startResponderForegroundService" -> {
                        val serviceIntent = Intent(this@MainActivity, ResponderForegroundService::class.java).apply {
                            action = ResponderForegroundService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    }
                    "stopResponderForegroundService" -> {
                        val serviceIntent = Intent(this@MainActivity, ResponderForegroundService::class.java).apply {
                            action = ResponderForegroundService.ACTION_STOP
                        }
                        stopService(serviceIntent)
                        result.success(true)
                    }
                    "isResponderForegroundServiceRunning" -> {
                        result.success(ResponderForegroundService.isServiceRunning)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Dedicated Push-to-Talk Voice Assistant Channel
        voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> {
                        val outputPath = call.argument<String>("outputPath")
                            ?: File(cacheDir, "voice_recording_${System.currentTimeMillis()}.m4a").absolutePath
                        try {
                            mediaRecorder?.release()
                            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                MediaRecorder(this@MainActivity)
                            } else {
                                @Suppress("DEPRECATION")
                                MediaRecorder()
                            }.apply {
                                setAudioSource(MediaRecorder.AudioSource.MIC)
                                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                                setAudioSamplingRate(44100)
                                setAudioEncodingBitRate(96000)
                                setOutputFile(outputPath)
                                prepare()
                                start()
                            }
                            currentRecordingPath = outputPath
                            result.success(outputPath)
                        } catch (e: Exception) {
                            mediaRecorder?.release()
                            mediaRecorder = null
                            result.error("RECORDING_FAILED", e.message, null)
                        }
                    }
                    "stopRecording" -> {
                        try {
                            mediaRecorder?.apply {
                                stop()
                                release()
                            }
                            mediaRecorder = null
                            val path = currentRecordingPath
                            currentRecordingPath = null
                            result.success(path)
                        } catch (e: Exception) {
                            mediaRecorder?.release()
                            mediaRecorder = null
                            result.error("STOP_RECORDING_FAILED", e.message, null)
                        }
                    }
                    "cancelRecording" -> {
                        try {
                            mediaRecorder?.apply {
                                try { stop() } catch (_: Exception) {}
                                release()
                            }
                            mediaRecorder = null
                            currentRecordingPath?.let { path ->
                                try { File(path).delete() } catch (_: Exception) {}
                            }
                            currentRecordingPath = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "playAudioBytes" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("INVALID_AUDIO", "Empty audio bytes", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val tempFile = File(cacheDir, "tts_response_${System.currentTimeMillis()}.mp3")
                            FileOutputStream(tempFile).use { it.write(bytes) }
                            mediaPlayer?.apply {
                                if (isPlaying) stop()
                                release()
                            }
                            mediaPlayer = MediaPlayer().apply {
                                setDataSource(tempFile.absolutePath)
                                setOnCompletionListener {
                                    try { tempFile.delete() } catch (_: Exception) {}
                                }
                                prepare()
                                start()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            mediaPlayer?.release()
                            mediaPlayer = null
                            result.error("PLAYBACK_FAILED", e.message, null)
                        }
                    }
                    "playAudioFile" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrEmpty()) {
                            result.error("INVALID_PATH", "Empty file path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            mediaPlayer?.apply {
                                if (isPlaying) stop()
                                release()
                            }
                            mediaPlayer = MediaPlayer().apply {
                                setDataSource(filePath)
                                prepare()
                                start()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            mediaPlayer?.release()
                            mediaPlayer = null
                            result.error("PLAYBACK_FAILED", e.message, null)
                        }
                    }
                    "stopAudioPlayback" -> {
                        try {
                            mediaPlayer?.apply {
                                if (isPlaying) stop()
                                release()
                            }
                            mediaPlayer = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "isAudioPlaying" -> {
                        val playing = mediaPlayer?.isPlaying ?: false
                        result.success(playing)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // If an emergency was tapped prior to engine configuration, deliver it now
        pendingEmergencyId?.let { id ->
            notificationChannel?.invokeMethod("onNotificationTapped", id)
        }

        // Forward Android 15 FGS timeout events to Flutter
        ResponderForegroundService.onTimeoutListener = {
            runOnUiThread {
                notificationChannel?.invokeMethod("onResponderModeTimedOut", null)
            }
        }
    }

    override fun onDestroy() {
        ResponderForegroundService.onTimeoutListener = null
        try {
            mediaRecorder?.release()
            mediaRecorder = null
        } catch (_: Exception) {}
        try {
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun showNativeEmergencyNotification(
        notificationId: Int,
        title: String,
        body: String,
        emergencyId: String?,
        useVoiceAlert: Boolean = true
    ) {
        val clickIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!emergencyId.isNullOrEmpty()) {
                putExtra("emergencyId", emergencyId)
            }
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            clickIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Check if voice resource is available and requested
        val voiceResId = resources.getIdentifier("emergency_alert_voice", "raw", packageName)
        val targetChannelId = if (useVoiceAlert && voiceResId != 0) {
            EMERGENCY_VOICE_CHANNEL_ID
        } else {
            EMERGENCY_CHANNEL_ID
        }

        val builder = NotificationCompat.Builder(this, targetChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVibrate(longArrayOf(0, 500, 200, 500))

        if (targetChannelId == EMERGENCY_VOICE_CHANNEL_ID && voiceResId != 0) {
            val soundUri = Uri.parse("android.resource://$packageName/$voiceResId")
            builder.setSound(soundUri)
        } else {
            builder.setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE)
        }

        val notificationManager = NotificationManagerCompat.from(this)
        try {
            notificationManager.notify(notificationId, builder.build())
        } catch (_: SecurityException) {
            // Handled safely if user has not yet granted notification permission
        }
    }
}
