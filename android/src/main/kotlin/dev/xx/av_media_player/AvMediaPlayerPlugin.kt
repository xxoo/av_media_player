package dev.xx.av_media_player

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.res.AssetFileDescriptor
import android.media.MediaPlayer
import android.view.Surface
import android.os.Handler
import android.os.Looper
import kotlin.math.max

class AvMediaPlayer(private val binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
	private val surfaceTextureEntry = binding.textureRegistry.createSurfaceTexture()
	val id = surfaceTextureEntry.id()
	private val eventChannel = EventChannel(binding.binaryMessenger, "av_media_player/$id")
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
	private var state = 0u
	private var finished = false
	private var hasVideo = false
	private var source: String? = null
	private var fd: AssetFileDescriptor? = null

	init {
		eventChannel.setStreamHandler(this)
		mediaPlayer.setOnPreparedListener {
			state = 2u
			mediaPlayer.setVolume(volume, volume)
			if (mediaPlayer.duration > 0) {
				//to ensure the first frame is loaded
				mediaPlayer.seekTo(0)
				stillPreparing = true
			} else if (source != null) {
				eventSink?.success(mapOf(
					"event" to "mediaInfo",
					"duration" to max(mediaPlayer.duration, 0),
					"source" to source
				))
			}
		}
		mediaPlayer.setOnVideoSizeChangedListener { _, _, _ ->
			if (state > 0u) {
				if (mediaPlayer.videoWidth > 0 && mediaPlayer.videoHeight > 0) {
					if (!hasVideo) {
						hasVideo = true
						mediaPlayer.setSurface(surface)
					}
				} else if (hasVideo) {
					hasVideo = false
					mediaPlayer.setSurface(null)
				}
				eventSink?.success(mapOf(
					"event" to "videoSize",
					"width" to mediaPlayer.videoWidth.toDouble(),
					"height" to mediaPlayer.videoHeight.toDouble()
				))
			}
		}
		mediaPlayer.setOnCompletionListener {
			if (state == 3u) {
				if (mediaPlayer.duration <= 0) {
					close()
				} else if (looping) {
					play()
				} else {
					state = 2u
					position = 0
					bufferPosition = 0
					finished = true
				}
				eventSink?.success(mapOf("event" to "finished"))
			}
		}
		mediaPlayer.setOnErrorListener { _, what, extra ->
			if (state != 0u) {
				close()
				eventSink?.success(mapOf(
					"event" to "error",
					"value" to "$what,$extra"
				))
			}
			true
		}
		mediaPlayer.setOnInfoListener { _, what, _ ->
			if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to true
				))
			} else if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to false
				))
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
			if (state > 1u) {
				val bufferPos: Int = mediaPlayer.duration * percent / 100
				val pos = mediaPlayer.currentPosition
				val realBufferPosition = max(bufferPos,  pos)
				if (realBufferPosition != bufferPosition) {
					bufferPosition = realBufferPosition
					eventSink?.success(mapOf(
						"event" to "buffer",
						"begin" to pos,
						"end" to bufferPosition
					))
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
		state = 1u
		if (hasVideo) {
			mediaPlayer.setSurface(null)
		}
		try {
			if (source.startsWith("asset://")) {
				fd = binding.applicationContext.assets.openFd(binding.flutterAssets.getAssetFilePathBySubpath(source.substring(8)))
				mediaPlayer.setDataSource(fd!!)
			} else {
				mediaPlayer.setDataSource(source)
			}
			mediaPlayer.prepareAsync()
		} catch (e: Exception) {
			eventSink?.success(mapOf(
				"event" to "error",
				"value" to e.toString()
			))
		}
	}

	fun close() {
		source = null
		finished = false
		hasVideo = false
		state = 0u
		position = 0
		bufferPosition = 0
		stillPreparing = false
		mediaPlayer.setSurface(null)
		mediaPlayer.reset()
		fd?.close()
		fd = null
	}

	fun play() {
		if (state > 1u) {
			finished = false
			state = 3u
			mediaPlayer.playbackParams = mediaPlayer.playbackParams.setSpeed(speed)
			if (!watching && mediaPlayer.duration > 0) {
				startWatcher()
			}
		}
	}

	fun pause() {
		if (state == 3u) {
			state = 2u
			mediaPlayer.pause()
		}
	}

	fun seekTo(pos: Int) {
		if (mediaPlayer.duration <= 0 || mediaPlayer.currentPosition == pos) {
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
			eventSink?.success(mapOf(
				"event" to "position",
				"value" to pos
			))
		}
	}

	override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
		eventSink = events
	}

	override fun onCancel(arguments: Any?) {
		eventSink = null
	}
}

class AvMediaPlayerPlugin: FlutterPlugin {
	private lateinit var methodChannel: MethodChannel
	private val players = mutableMapOf<Long, AvMediaPlayer>()

	private fun clear() {
		for (player in players.values) {
			player.dispose()
		}
		players.clear()
	}

	override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		methodChannel = MethodChannel(binding.binaryMessenger, "av_media_player")
		methodChannel.setMethodCallHandler { call, result ->
			when (call.method) {
				"create" -> {
					val player = AvMediaPlayer(binding)
					players[player.id] = player
					result.success(player.id)
				}
				"dispose" -> {
					result.success(null)
					if (call.arguments == null) {
						clear()
					} else {
						val id = (call.arguments as Int).toLong()
						players[id]?.dispose()
						players.remove(id)
					}
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

	override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		methodChannel.setMethodCallHandler(null)
		clear()
	}
}