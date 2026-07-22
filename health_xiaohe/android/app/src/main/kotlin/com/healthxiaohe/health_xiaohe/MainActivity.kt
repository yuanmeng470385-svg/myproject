package com.healthxiaohe.health_xiaohe

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.*
import android.media.audiofx.AcousticEchoCanceler
import android.os.Process
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.*

class MainActivity : FlutterActivity() {
    companion object {
        private const val AUDIO_PERM_REQ = 1001
    }

    // --- AudioEngine: 统一管理录音和播放，解决回声和延迟 ---
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var recording = false
    private var outputBufferSize = 0
    private var recChannel: MethodChannel? = null

    // 后台播放：AudioTrack.write 在 MODE_STREAM 下缓冲满会阻塞，必须移出主线程。
    // DashScope 的音频 delta 高频小块，入队后由专用线程顺序写入，主线程不再被冻结。
    private var playbackThread: Thread? = null
    private val playbackQueue = java.util.concurrent.LinkedBlockingQueue<ByteArray>()
    @Volatile private var playing = false

    private fun stopPlaybackThread() {
        playing = false
        playbackThread?.interrupt()
        // 等线程退出再让调用方 release audioTrack，避免与后台 write 并发访问
        try { playbackThread?.join(200) } catch (_: Exception) {}
        playbackThread = null
        playbackQueue.clear()
    }

    private fun safeCleanup() {
        try { echoCanceler?.enabled = false; echoCanceler?.release() } catch (_: Exception) {}
        echoCanceler = null
        try { audioRecord?.stop(); audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        recording = false
    }

    private fun safeStopTrack() {
        try { audioTrack?.pause(); audioTrack?.flush() } catch (_: Exception) {}
    }

    private fun safeDisposeTrack() {
        try { audioTrack?.stop(); audioTrack?.release() } catch (_: Exception) {}
        audioTrack = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --- Recorder Channel ---
        recChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.healthxiaohe/audio_recorder")
        recChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                    val bufferSize = AudioRecord.getMinBufferSize(sampleRate,
                        AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                    audioRecord = AudioRecord.Builder()
                        .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                        .setAudioFormat(AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                            .build())
                        .setBufferSizeInBytes(bufferSize * 2)
                        .build()
                    // 尝试开启硬件回声消除
                    try {
                        if (AcousticEchoCanceler.isAvailable()) {
                            echoCanceler = AcousticEchoCanceler.create(audioRecord!!.audioSessionId)
                            echoCanceler?.enabled = true
                        }
                    } catch (_: Exception) {}
                    audioRecord?.startRecording()
                    recording = true
                    // 后台线程持续读取PCM；invokeMethod 必须切回主线程
                    Thread {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
                        val buf = ByteArray(bufferSize)
                        while (recording) {
                            val len = audioRecord?.read(buf, 0, buf.size) ?: break
                            if (len > 0) {
                                val chunk = buf.copyOf(len)
                                runOnUiThread { recChannel?.invokeMethod("onAudio", chunk) }
                            }
                        }
                    }.start()
                    result.success(true)
                }
                "stop" -> { safeCleanup(); result.success(true) }
                "requestPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this, Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        result.success(true)
                    } else {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            AUDIO_PERM_REQ
                        )
                        result.success(false) // 本次未授权，等回调
                    }
                }
                else -> result.notImplemented()
            }
        }

        // --- Player Channel ---
        val playerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.healthxiaohe/audio_player")
        playerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    // 重新初始化前先停掉旧线程/旧 track，避免重复通话时泄漏
                    stopPlaybackThread()
                    safeDisposeTrack()
                    val sampleRate = call.argument<Int>("sampleRate") ?: 24000
                    outputBufferSize = AudioTrack.getMinBufferSize(sampleRate,
                        AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
                    audioTrack = AudioTrack.Builder()
                        .setAudioAttributes(AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build())
                        .setAudioFormat(AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build())
                        .setBufferSizeInBytes(outputBufferSize * 2)
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .build()
                    // 默认开扬声器 + 最大音量，否则走听筒音量极小
                    val am = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    am.mode = AudioManager.MODE_NORMAL
                    am.isSpeakerphoneOn = true
                    audioTrack?.play()
                    // 启动后台播放线程：阻塞写在这里发生，不再冻结 UI 主线程
                    playing = true
                    playbackThread = Thread {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
                        while (playing) {
                            try {
                                val data = playbackQueue.take() // 队空时阻塞等待
                                audioTrack?.write(data, 0, data.size)
                            } catch (e: InterruptedException) {
                                break
                            } catch (_: Exception) {}
                        }
                    }.apply { start() }
                    result.success(true)
                }
                "play" -> {
                    try {
                        audioTrack?.play() // resume after pause
                        playbackQueue.offer(call.arguments as ByteArray) // 入队即返回，不阻塞主线程
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }
                "speaker" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    val am = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    am.mode = if (on) AudioManager.MODE_NORMAL else AudioManager.MODE_IN_COMMUNICATION
                    am.isSpeakerphoneOn = on
                    result.success(true)
                }
                "stop" -> {
                    // 打断：丢弃堆积未播的音频 delta，立即静音
                    playbackQueue.clear()
                    safeStopTrack()
                    result.success(true)
                }
                "dispose" -> {
                    stopPlaybackThread()
                    safeDisposeTrack()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
