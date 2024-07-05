package dev.xx.av_media_player

import kotlin.math.round
import android.os.Handler
import android.view.Surface
import androidx.media3.common.VideoSize
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class AvMediaPlayer(private val binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler, Player.Listener {
	private val surfaceTextureEntry = binding.textureRegistry.createSurfaceTexture()
	val id = surfaceTextureEntry.id().toInt()
	private val surface = Surface(surfaceTextureEntry.surfaceTexture())
	private val exoPlayer = ExoPlayer.Builder(binding.applicationContext).build()
	private val handler = Handler(exoPlayer.applicationLooper)
	private val eventChannel = EventChannel(binding.binaryMessenger, "av_media_player/$id")

	private var speed = 1F
	private var volume = 1F
	private var looping = false
	private var position = 0L
	private var eventSink: EventChannel.EventSink? = null
	private var watching = false
	private var buffering = false
	private var stillPreparing = false
	private var bufferPosition = 0L
	private var state: UByte = 0U //0: idle, 1: opening, 2: ready, 3: playing
	private var source: String? = null
	private var seeking = false
	private var networking = false

	init {
		binding.textureRegistry.createSurfaceProducer()
		eventChannel.setStreamHandler(this)
		exoPlayer.addListener(this)
	}

	fun dispose() {
		exoPlayer.release()
		surface.release()
		surfaceTextureEntry.release()
		handler.removeCallbacksAndMessages(null)
		eventSink?.endOfStream()
	}

	fun open(source: String) {
		close()
		var url = ""
		if (source.startsWith("asset://")) {
			url = "asset:///${binding.flutterAssets.getAssetFilePathBySubpath(source.substring(8))}"
		} else if (source.startsWith("file://") || !source.contains("://")) {
			url = if (source.startsWith("file://")) source else "file://$source"
		} else {
			url = source
			networking = true
		}
		try {
			exoPlayer.setMediaItem(MediaItem.fromUri(url))
			exoPlayer.prepare()
			exoPlayer.setVideoSurface(surface)
			state = 1U
			this.source = source
		} catch (e: Exception) {
			eventSink?.success(mapOf(
				"event" to "error",
				"value" to e.toString()
			))
		}
	}

	fun close() {
		source = null
		seeking = false
		networking = false
		state = 0U
		position = 0
		bufferPosition = 0
		stillPreparing = false
		exoPlayer.playWhenReady = false
		exoPlayer.stop()
		exoPlayer.clearMediaItems()
		exoPlayer.setVideoSurface(null)
	}

	fun play() {
		if (state.compareTo(2U) == 0) {
			state = 3U
			justPlay()
			if (exoPlayer.playbackState == Player.STATE_BUFFERING) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to true
				))
			}
		}
	}

	fun pause() {
		if (state > 2U) {
			state = 2U
			exoPlayer.playWhenReady = false
		}
	}

	fun seekTo(pos: Long) {
		if (exoPlayer.isCurrentMediaItemLive || exoPlayer.currentPosition == pos) {
			eventSink?.success(mapOf("event" to "seekEnd"))
		} else {
			seeking = true
			exoPlayer.seekTo(pos)
		}
	}

	fun setVolume(vol: Float) {
		volume = vol
		exoPlayer.volume = vol
	}

	fun setSpeed(spd: Float) {
		speed = spd
		exoPlayer.playbackParameters = exoPlayer.playbackParameters.withSpeed(speed)
	}

	fun setLooping(loop: Boolean) {
		looping = loop
	}

	private fun seekEnd() {
		seeking = false
		if (!watching) {
			watchPosition()
		}
		eventSink?.success(mapOf("event" to "seekEnd"))
	}

	private fun justPlay() {
		if (exoPlayer.playbackState == Player.STATE_ENDED) {
			exoPlayer.seekTo(0)
		}
		exoPlayer.playWhenReady = true
		if (!watching && !exoPlayer.isCurrentMediaItemLive) {
			startWatcher()
		}
	}

	private fun startBuffering() {
		buffering = true
		handler.postDelayed({
			if (state > 0U && networking && exoPlayer.isLoading && !exoPlayer.isCurrentMediaItemLive) {
				startBuffering()
				watchBuffer()
			} else {
				buffering = false
			}
		}, 100)
	}

	private fun watchBuffer() {
		val bufferPos = exoPlayer.bufferedPosition
		if (bufferPos != bufferPosition && bufferPos > exoPlayer.currentPosition) {
			bufferPosition = bufferPos
			eventSink?.success(mapOf(
				"event" to "buffer",
				"begin" to exoPlayer.currentPosition,
				"end" to bufferPosition
			))
		}
	}

	private fun startWatcher() {
		watching = true
		handler.postDelayed({
			if (state > 2U && !exoPlayer.isCurrentMediaItemLive) {
				startWatcher()
			} else {
				watching = false
			}
			watchPosition()
		}, 10)
	}

	private fun watchPosition() {
		val pos = exoPlayer.currentPosition
		if (pos != position) {
			position = pos
			eventSink?.success(mapOf(
				"event" to "position",
				"value" to pos
			))
		}
	}

	override fun onVideoSizeChanged(videoSize: VideoSize) {
		super.onVideoSizeChanged(videoSize)
		if (state > 0U) {
			var w = 0F
			var h = 0F
			if (videoSize.unappliedRotationDegrees % 180 == 0) {
				w = round(videoSize.width * videoSize.pixelWidthHeightRatio)
				h = videoSize.height.toFloat()
			} else {
				w = videoSize.height.toFloat()
				h = round(videoSize.width * videoSize.pixelWidthHeightRatio)
			}
			eventSink?.success(mapOf(
				"event" to "videoSize",
				"width" to w,
				"height" to h
			))
		}
	}

	override fun onPlayerError(error: PlaybackException) {
		super.onPlayerError(error)
		if (state > 0U) {
			close()
			eventSink?.success(mapOf(
				"event" to "error",
				"value" to error.errorCodeName
			))
		}
	}

	override fun onPlaybackStateChanged(playbackState: Int) {
		super.onPlaybackStateChanged(playbackState)
		if (seeking && (playbackState == Player.STATE_READY || playbackState == Player.STATE_ENDED)) {
			seekEnd()
		} else if (playbackState == Player.STATE_READY) {
			if (state.compareTo(1U) == 0) {
				state = 2U
				exoPlayer.volume = volume
				eventSink?.success(mapOf(
					"event" to "mediaInfo",
					"duration" to if (exoPlayer.isCurrentMediaItemLive) 0 else exoPlayer.duration,
					"source" to source
				))
			} else if (state > 2U) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to false
				))
			}
		} else if (playbackState == Player.STATE_ENDED) {
			if (state > 1U && !exoPlayer.isCurrentMediaItemLive) {
				eventSink?.success(mapOf(
					"event" to "position",
					"value" to exoPlayer.duration
				))
			}
			if (state > 2U) {
				if (exoPlayer.isCurrentMediaItemLive) {
					close()
				} else if (looping) {
					justPlay()
				} else {
					state = 2U
				}
				eventSink?.success(mapOf("event" to "finished"))
			}
		} else if (playbackState == Player.STATE_BUFFERING) {
			if (state > 2U) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to true
				))
			}
		}
	}

	override fun onIsLoadingChanged(isLoading: Boolean) {
		super.onIsLoadingChanged(isLoading)
		if (networking && !exoPlayer.isCurrentMediaItemLive) {
			if (isLoading) {
				if (!buffering) {
					startBuffering()
				}
			} else if (buffering) {
				buffering = false
				watchBuffer()
			}
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
	private val players = mutableMapOf<Int, AvMediaPlayer>()

	private fun clear() {
		for (player in players.values) {
			player.dispose()
		}
		players.clear()
	}

	override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		methodChannel = MethodChannel(binding.binaryMessenger, "av_media_player")
		methodChannel.setMethodCallHandler { call, result ->
			var returned = false
			when (call.method) {
				"create" -> {
					val player = AvMediaPlayer(binding)
					players[player.id] = player
					result.success(player.id)
					returned = true
				}
				"dispose" -> {
					val id = call.arguments
					if (id is Int) {
						players[id]?.dispose()
						players.remove(id)
					} else {
						clear()
					}
				}
				"open" -> {
					players[call.argument<Int>("id")!!]?.open(call.argument<String>("value")!!)
				}
				"close" -> {
					players[call.arguments as Int]?.close()
				}
				"play" -> {
					players[call.arguments as Int]?.play()
				}
				"pause" -> {
					players[call.arguments as Int]?.pause()
				}
				"seekTo" -> {
					players[call.argument<Int>("id")!!]?.seekTo(call.argument<Long>("value")!!)
				}
				"setVolume" -> {
					players[call.argument<Int>("id")!!]?.setVolume(call.argument<Float>("value")!!)
				}
				"setSpeed" -> {
					players[call.argument<Int>("id")!!]?.setSpeed(call.argument<Float>("value")!!)
				}
				"setLooping" -> {
					players[call.argument<Int>("id")!!]?.setLooping(call.argument<Boolean>("value")!!)
				}
				else -> {
					result.notImplemented()
					returned = true
				}
			}
			if (!returned) {
				result.success(null)
			}
		}
	}

	override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		methodChannel.setMethodCallHandler(null)
		clear()
	}
}