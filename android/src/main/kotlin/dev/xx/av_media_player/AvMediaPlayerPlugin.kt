package dev.xx.av_media_player

import android.graphics.Color
import android.graphics.PorterDuff
import android.os.Handler
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

@UnstableApi class AvMediaPlayer(private val binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler, Player.Listener {
	companion object {
		private val trackTypes = mapOf(
			C.TRACK_TYPE_VIDEO to "video",
			C.TRACK_TYPE_AUDIO to "audio",
			C.TRACK_TYPE_TEXT to "sub"
		)
	}
	private val surfaceEntry = binding.textureRegistry.createSurfaceTexture()
	private val subSurfaceEntry = binding.textureRegistry.createSurfaceTexture()
	val id = surfaceEntry.id().toInt()
	val subId = subSurfaceEntry.id().toInt()
	private val surface = Surface(surfaceEntry.surfaceTexture())
	private val subSurfaceTexture = subSurfaceEntry.surfaceTexture()
	private val subSurface = Surface(subSurfaceTexture)
	private val exoPlayer = ExoPlayer.Builder(binding.applicationContext).build()
	private val handler = Handler(exoPlayer.applicationLooper)
	private val eventChannel = EventChannel(binding.binaryMessenger, "av_media_player/$id")
	private val subtitlePainter = SubtitlePainter(binding.applicationContext)

	private var speed = 1F
	private var volume = 1F
	private var looping = false
	private var position = 0L
	private var eventSink: EventChannel.EventSink? = null
	private var watching = false
	private var buffering = false
	private var bufferPosition = 0L
	private var state: UByte = 0U //0: idle, 1: opening, 2: ready, 3: playing
	private var source: String? = null
	private var seeking = false
	private var networking = false
	private var showSubtitle = false

	init {
		binding.textureRegistry.createSurfaceProducer()
		eventChannel.setStreamHandler(this)
		exoPlayer.addListener(this)
		exoPlayer.setVideoSurface(surface)
	}

	fun dispose() {
		handler.removeCallbacksAndMessages(null)
		exoPlayer.release()
		surface.release()
		subSurface.release()
		surfaceEntry.release()
		subSurfaceEntry.release()
		eventSink?.endOfStream()
	}

	fun open(source: String): Object? {
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
			exoPlayer.setMediaItem(if (url.contains(".m3u8")) MediaItem.Builder().setMimeType(MimeTypes.APPLICATION_M3U8).setUri(url).build() else MediaItem.fromUri(url))
			exoPlayer.prepare()
			state = 1U
			this.source = source
		} catch (e: Exception) {
			eventSink?.success(mapOf(
				"event" to "error",
				"value" to e.toString()
			))
		}
		return null
	}

	fun close(): Object? {
		source = null
		seeking = false
		networking = false
		state = 0U
		position = 0
		bufferPosition = 0
		exoPlayer.playWhenReady = false
		exoPlayer.stop()
		exoPlayer.clearMediaItems()
		clearSubtitle()
		if (exoPlayer.trackSelectionParameters.overrides.isNotEmpty()) {
			exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().clearOverrides().build()
		}
		return null
	}

	fun play(): Object? {
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
		return null
	}

	fun pause(): Object? {
		if (state > 2U) {
			state = 2U
			exoPlayer.playWhenReady = false
		}
		return null
	}

	fun seekTo(pos: Long): Object? {
		if (exoPlayer.isCurrentMediaItemLive || exoPlayer.currentPosition == pos) {
			eventSink?.success(mapOf("event" to "seekEnd"))
		} else {
			seeking = true
			exoPlayer.seekTo(pos)
		}
		return null
	}

	fun setVolume(vol: Float): Object? {
		volume = vol
		exoPlayer.volume = vol
		return null
	}

	fun setSpeed(spd: Float): Object? {
		speed = spd
		exoPlayer.playbackParameters = exoPlayer.playbackParameters.withSpeed(speed)
		return null
	}

	fun setLooping(loop: Boolean): Object? {
		looping = loop
		return null
	}

	fun setMaxResolution(width: Int, height: Int): Object? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setMaxVideoSize(width, height).build()
		return null
	}

	fun setMaxBitrate(bitrate: Int): Object? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setMaxVideoBitrate(bitrate).build()
		return null
	}

	fun setPreferredAudioLanguage(language: String): Object? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setPreferredAudioLanguage(if (language.isEmpty()) null else language).build()
		return null
	}

	fun setPreferredSubtitleLanguage(language: String): Object? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setPreferredTextLanguage(if (language.isEmpty()) null else language).build()
		return null
	}

	fun setShowSubtitle(show: Boolean): Object? {
		showSubtitle = show
		if (showSubtitle) {
			clearSubtitle()
		}
		return null
	}

	fun overrideTrack(groupId: Int, trackId: Int, enabled: Boolean): Object? {
		if (state > 1U) {
			val group = exoPlayer.currentTracks.groups[groupId]
			if (group != null && trackTypes.contains(group.type) && group.isTrackSupported(trackId, false)) {
				if (enabled) {
					exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackId)).build()
				} else if (exoPlayer.trackSelectionParameters.overrides.contains(group.mediaTrackGroup) && exoPlayer.trackSelectionParameters.overrides[group.mediaTrackGroup]!!.trackIndices.contains(trackId)) {
					exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().clearOverride(group.mediaTrackGroup).build()
				}
			}
		}
		return null
	}

	private fun clearSubtitle() {
		val canvas = subSurface.lockHardwareCanvas()
		canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
		subSurface.unlockCanvasAndPost(canvas)
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
				val allTracks = mutableMapOf<String, MutableMap<String, Any?>>()
				for (i in 0 until exoPlayer.currentTracks.groups.size) {
					val group = exoPlayer.currentTracks.groups[i]
					if (trackTypes.contains(group.type)) {
						for (j in 0 until group.length) {
							if (group.isTrackSupported(j, false)) {
								val format = group.getTrackFormat(j)
								if (format.roleFlags != C.ROLE_FLAG_TRICK_PLAY) {
									val track = mutableMapOf<String, Any?>(
										"type" to trackTypes[group.type]!!,
										"title" to format.label,
										"language" to format.language,
										"format" to if (format.codecs == null) format.sampleMimeType else format.codecs,
										"bitRate" to if (format.averageBitrate > 0) format.averageBitrate else format.bitrate
									)
									if (group.type == C.TRACK_TYPE_VIDEO) {
										track["width"] = format.width
										track["height"] = format.height
										track["frameRate"] = format.frameRate
										track["isHdr"] = ColorInfo.isTransferHdr(format.colorInfo)
									} else if (group.type == C.TRACK_TYPE_AUDIO) {
										track["channels"] = format.channelCount
										track["sampleRate"] = format.sampleRate
									}
									allTracks["$i.$j"] = track
								}
							}
						}
					}
				}
				eventSink?.success(mapOf(
					"event" to "mediaInfo",
					"duration" to if (exoPlayer.isCurrentMediaItemLive) 0 else exoPlayer.duration,
					"tracks" to allTracks,
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

	override fun onVideoSizeChanged(videoSize: VideoSize) {
		super.onVideoSizeChanged(videoSize)
		if (state > 0U) {
			val width: Int
			val height: Int
			if (videoSize.unappliedRotationDegrees % 180 == 0) {
				width = Math.round(videoSize.width * videoSize.pixelWidthHeightRatio)
				height = videoSize.height
			} else {
				width = videoSize.height
				height = Math.round(videoSize.width * videoSize.pixelWidthHeightRatio)
			}
			if (width > 0 && height > 0) {
				subSurfaceTexture.setDefaultBufferSize(width, height)
			}
			eventSink?.success(mapOf(
				"event" to "videoSize",
				"width" to width.toFloat(),
				"height" to height.toFloat()
			))
		}
	}

	override fun onCues(cueGroup: CueGroup) {
		super.onCues(cueGroup)
		if (state > 0U && showSubtitle) {
			val canvas = subSurface.lockHardwareCanvas()
			canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
			for (cue in cueGroup.cues) {
				subtitlePainter.draw(cue, canvas)
			}
			subSurface.unlockCanvasAndPost(canvas)
		}
	}

	override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
		eventSink = events
	}

	override fun onCancel(arguments: Any?) {
		eventSink = null
	}
}

@UnstableApi class AvMediaPlayerPlugin: FlutterPlugin {
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
			when (call.method) {
				"create" -> {
					val player = AvMediaPlayer(binding)
					players[player.id] = player
					result.success(mapOf(
						"id" to player.id,
						"subId" to player.subId
					))
				}
				"dispose" -> {
					val id = call.arguments
					if (id is Int) {
						players[id]?.dispose()
						players.remove(id)
					} else {
						clear()
					}
					result.success(null)
				}
				"open" -> {
					result.success(players[call.argument<Int>("id")!!]?.open(call.argument<String>("value")!!))
				}
				"close" -> {
					result.success(players[call.arguments as Int]?.close())
				}
				"play" -> {
					result.success(players[call.arguments as Int]?.play())
				}
				"pause" -> {
					result.success(players[call.arguments as Int]?.pause())
				}
				"seekTo" -> {
					result.success(players[call.argument<Int>("id")!!]?.seekTo(call.argument<Long>("value")!!))
				}
				"setVolume" -> {
					result.success(players[call.argument<Int>("id")!!]?.setVolume(call.argument<Float>("value")!!))
				}
				"setSpeed" -> {
					result.success(players[call.argument<Int>("id")!!]?.setSpeed(call.argument<Float>("value")!!))
				}
				"setLooping" -> {
					result.success(players[call.argument<Int>("id")!!]?.setLooping(call.argument<Boolean>("value")!!))
				}
				"setMaxResolution" -> {
					result.success(players[call.argument<Int>("id")!!]?.setMaxResolution(call.argument<Int>("width")!!, call.argument<Int>("height")!!))
				}
				"setMaxBitrate" -> {
					result.success(players[call.argument<Int>("id")!!]?.setMaxBitrate(call.argument<Int>("value")!!))
				}
				"setPreferredAudioLanguage" -> {
					result.success(players[call.argument<Int>("id")!!]?.setPreferredAudioLanguage(call.argument<String>("value")!!))
				}
				"setPreferredSubtitleLanguage" -> {
					result.success(players[call.argument<Int>("id")!!]?.setPreferredSubtitleLanguage(call.argument<String>("value")!!))
				}
				"overrideTrack" -> {
					result.success(players[call.argument<Int>("id")!!]?.overrideTrack(call.argument<Int>("groupId")!!, call.argument<Int>("trackId")!!, call.argument<Boolean>("value")!!))
				}
				"setShowSubtitle" -> {
					result.success(players[call.argument<Int>("id")!!]?.setShowSubtitle(call.argument<Boolean>("value")!!))
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