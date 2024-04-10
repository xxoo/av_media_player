package dev.xx.av_media_player

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.view.Surface
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import kotlin.math.max

class AVMediaPlayerPlugin: FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var binding: FlutterPlugin.FlutterPluginBinding
  private lateinit var methodChannel: MethodChannel
  private val players = mutableMapOf<Long, AVMediaPlayer>()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    binding = flutterPluginBinding
    methodChannel = MethodChannel(binding.binaryMessenger, "avMediaPlayer")
    methodChannel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    for (player in players.values) {
      player.dispose()
    }
    players.clear()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "create" -> {
        val player = AVMediaPlayer(binding)
        players[player.id] = player
        result.success(player.id)
      }
      "dispose" -> {
        result.success(null)
        val id = (call.arguments as Int).toLong()
        players[id]?.dispose()
        players.remove(id)
      }
      "open" -> {
        result.success(null)
        val id = call.argument<Long>("id")!!
        val source = call.argument<String>("value")!!
        players[id]?.open(source)
      }
      "close" -> {
        result.success(null)
        val id = (call.arguments as Int).toLong()
        players[id]?.close()
      }
      "play" -> {
        result.success(null)
        val id = (call.arguments as Int).toLong()
        players[id]?.play()
      }
      "pause" -> {
        result.success(null)
        val id = (call.arguments as Int).toLong()
        players[id]?.pause()
      }
      "seekTo" -> {
        val id = call.argument<Long>("id")!!
        val pos = call.argument<Int>("value")!!
        players[id]?.seekTo(pos)
        result.success(null)
      }
      "setVolume" -> {
        result.success(null)
        val id = call.argument<Long>("id")!!
        val vol = call.argument<Float>("value")!!
        players[id]?.setVolume(vol)
      }
      "setSpeed" -> {
        result.success(null)
        val id = call.argument<Long>("id")!!
        val spd = call.argument<Float>("value")!!
        players[id]?.setSpeed(spd)
      }
      "setLooping" -> {
        result.success(null)
        val id = call.argument<Long>("id")!!
        val looping = call.argument<Boolean>("value")!!
        players[id]?.setLooping(looping)
      }
      else -> {
        result.notImplemented()
      }
    }
  }
}

class AVMediaPlayer(binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
  private val surfaceTextureEntry = binding.textureRegistry.createSurfaceTexture()
  val id = surfaceTextureEntry.id()
  private val eventChannel = EventChannel(binding.binaryMessenger, "avMediaPlayer/$id")
  private val surface = Surface(surfaceTextureEntry.surfaceTexture())
  private val mediaPlayer = MediaPlayer()
  private val handler = Handler(Looper.myLooper() ?: Looper.getMainLooper())

  private var speed = 1f
  private var volume = 1f
  private var looping = false
  private var position = 0
  private var eventSink: EventChannel.EventSink? = null
  private var watching = false
  private var stillPreparing = false
  private var bufferPosition = 0
  //0: idle, 1: opening, 2: ready, 3: playing
  private var state = 0
  private var finished = false
  private var source: String? = null

  init {
    eventChannel.setStreamHandler(this)
    mediaPlayer.setOnPreparedListener {
      state = 2
      if (mediaPlayer.duration > 0 && mediaPlayer.videoWidth > 0 && mediaPlayer.videoHeight > 0) {
        mediaPlayer.setSurface(surface)
      }
      mediaPlayer.setVolume(volume, volume)
      //to ensure the first frame is rendered
      mediaPlayer.seekTo(0)
      stillPreparing = true
    }
    mediaPlayer.setOnCompletionListener {
      if (state == 3) {
        if (looping) {
          play()
        } else {
          state = 2
          position = 0
          bufferPosition = 0
          finished = true
        }
        eventSink?.success(mapOf("event" to "finished"))
      }
    }
    mediaPlayer.setOnErrorListener { _, what, extra ->
      if (state != 0) {
      	close()
      	eventSink?.success(mapOf("event" to "error", "value" to "$what,$extra"))
      }
      true
    }
    mediaPlayer.setOnInfoListener { _, what, _ ->
      if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) {
        eventSink?.success(mapOf("event" to "loading", "value" to true))
      } else if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) {
        eventSink?.success(mapOf("event" to "loading", "value" to false))
      }
      true
    }
    mediaPlayer.setOnSeekCompleteListener {
      //the video is real prepared now
      if (stillPreparing) {
        stillPreparing = false
        if (source != null) {
          eventSink?.success(mapOf(
            "event" to "mediaInfo",
            "duration" to mediaPlayer.duration,
            "width" to mediaPlayer.videoWidth,
            "height" to mediaPlayer.videoHeight,
            "source" to source
          ))
        }
      } else {
        if (!watching) {
          watchPosition()
        }
        eventSink?.success(mapOf("event" to "seekEnd"))
      }
    }
    mediaPlayer.setOnBufferingUpdateListener { _, percent ->
      if (state > 1) {
        val bufferPos: Int = mediaPlayer.duration * percent / 100
        val pos = mediaPlayer.currentPosition
        val realBufferPosition = max(bufferPos,  pos)
        if (realBufferPosition != bufferPosition) {
          bufferPosition = realBufferPosition
          eventSink?.success(mapOf("event" to "bufferChange", "begin" to pos, "end" to bufferPosition))
        }
      }
    }
  }

  fun dispose() {
    mediaPlayer.release()
    surface.release()
    surfaceTextureEntry.release()
    handler.removeCallbacksAndMessages(null)
    eventSink?.endOfStream()
  }

  fun open(source: String) {
    close()
    this.source = source
    state = 1
    mediaPlayer.setDataSource(source)
    mediaPlayer.prepareAsync()
  }

  fun close() {
    source = null
    finished = false
    state = 0
    position = 0
    bufferPosition = 0
    stillPreparing = false
    mediaPlayer.setSurface(null)
    mediaPlayer.reset()
  }

  fun play() {
    if (state > 1) {
      finished = false
      state = 3
      mediaPlayer.playbackParams = mediaPlayer.playbackParams.setSpeed(speed)
      if (!watching) {
        startWatcher()
      }
    }
  }

  fun pause() {
    if (state == 3) {
      state = 2
      mediaPlayer.pause()
    }
  }

  fun seekTo(pos: Int) {
    if (mediaPlayer.currentPosition == pos) {
      eventSink?.success(mapOf("event" to "seekEnd"))
    } else {
      finished = false
      mediaPlayer.seekTo(pos.toLong(), MediaPlayer.SEEK_CLOSEST)
    }
  }

  fun setVolume(vol: Float) {
    volume = vol
    mediaPlayer.setVolume(vol, vol)
  }

  fun setSpeed(spd: Float) {
    speed = spd
    if (mediaPlayer.isPlaying) {
      mediaPlayer.playbackParams = mediaPlayer.playbackParams.setSpeed(spd)
    }
  }

  fun setLooping(loop: Boolean) {
    looping = loop
  }

  private fun startWatcher() {
    watching = true
    handler.postDelayed({
      if (mediaPlayer.isPlaying) {
        startWatcher()
      } else {
        watching = false
      }
      if (watching || !finished) {
      	watchPosition()
      }
    }, 100)
  }

  private fun watchPosition() {
    val pos = mediaPlayer.currentPosition
    if (pos != position) {
      position = pos
      eventSink?.success(mapOf("event" to "position", "value" to pos))
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
}