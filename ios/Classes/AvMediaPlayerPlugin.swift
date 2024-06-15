import AVFoundation
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

class AvMediaPlayer: NSObject, FlutterTexture, FlutterStreamHandler {
	var id: Int64!
	private let textureRegistry: FlutterTextureRegistry
	private let avPlayer = AVPlayer()
	private var eventChannel: FlutterEventChannel!
	private var output: AVPlayerItemVideoOutput?
	private var eventSink: FlutterEventSink?
	private var watcher: Any?
	private var position = CMTime.zero
	private var bufferPosition = CMTime.zero
	private var speed: Float = 1
	private var volume: Float = 1
	private var looping = false
	private var reading: CMTime?
	private var rendering: CMTime?
	private var state: UInt8 = 0 //0: idle, 1: opening, 2: ready, 3: playing
	private var source: String?

#if os(macOS)
	private var displayLink: CVDisplayLink?
	func displayCallback(outputTime: CVTimeStamp) {
		if output != nil && displayLink != nil {
			let t = output!.itemTime(for: outputTime)
			if reading != t && rendering != t /*&& output!.hasNewPixelBuffer(forItemTime: t) */{
				textureRegistry.textureFrameAvailable(id)
				reading = t
			}
		}
	}
#else
	private var displayLink: CADisplayLink?
	@objc private func displayCallback() {
		if output != nil && displayLink != nil {
			let t = output!.itemTime(forHostTime: displayLink!.targetTimestamp)
			if reading != t && rendering != t /*&& output!.hasNewPixelBuffer(forItemTime: t) */{
				textureRegistry.textureFrameAvailable(id)
				reading = t
			}
		}
	}
#endif

	init(registrar: FlutterPluginRegistrar) {
#if os(macOS)
		textureRegistry = registrar.textures
		let messager = registrar.messenger
#else
		textureRegistry = registrar.textures()
		let messager = registrar.messenger()
#endif
		super.init()
		id = textureRegistry.register(self)
		eventChannel = FlutterEventChannel(name: "av_media_player/\(id!)", binaryMessenger: messager)
		eventChannel.setStreamHandler(self)
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus), options: .old, context: nil)
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.status), context: nil)
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.loadedTimeRanges), context: nil)
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.presentationSize), context: nil)
	}

	deinit {
		eventSink?(FlutterEndOfEventStream)
		eventChannel.setStreamHandler(nil)
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus))
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.status))
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.loadedTimeRanges))
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.presentationSize))
		textureRegistry.unregisterTexture(id)
	}

	func open(source: String) {
		let uri: URL?
		if source.starts(with: "asset://") {
			uri = URL(fileURLWithPath: Bundle.main.bundlePath + "/" + FlutterDartProject.lookupKey(forAsset: String(source.suffix(source.count - 8))))
		} else if source.contains("://") {
			uri = URL(string: source)
		} else {
			uri = URL(fileURLWithPath: source)
		}
		if uri == nil {
			eventSink?([
				"event": "error",
				"value": "Invalid source"
			])
		} else {
			close()
			self.source = source
			state = 1
			avPlayer.replaceCurrentItem(with: AVPlayerItem(asset: AVAsset(url: uri!)))
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(onFinish(notification:)),
				name: .AVPlayerItemDidPlayToEndTime,
				object: avPlayer.currentItem
			)
		}
	}

	func close() {
		state = 0
		position = .zero
		bufferPosition = .zero
		avPlayer.pause()
		if output != nil {
			avPlayer.currentItem?.remove(output!)
			output = nil
		}
		stopVideo()
		stopWatcher()
		source = nil
		reading = nil
		rendering = nil
		if avPlayer.currentItem != nil {
			NotificationCenter.default.removeObserver(
				self,
				name: .AVPlayerItemDidPlayToEndTime,
				object: avPlayer.currentItem
			)
			avPlayer.replaceCurrentItem(with: nil)
		}
	}

	func play() {
		if state > 1 {
			state = 3
			if watcher == nil && avPlayer.currentItem != nil && avPlayer.currentItem!.duration.seconds > 0 {
				watcher = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.01, preferredTimescale: 1000), queue: nil) { [weak self] time in
					if self != nil {
						if self!.avPlayer.rate == 0 || self!.avPlayer.error != nil {
							self!.stopWatcher()
						}
						self!.setPosition(time: time)
					}
				}
			}
			avPlayer.rate = speed
		}
	}

	func pause() {
		if state == 3 {
			state = 2
			avPlayer.pause()
		}
	}

	func seekTo(pos: CMTime) {
		if avPlayer.currentItem == nil || !(avPlayer.currentItem!.duration.seconds > 0) || avPlayer.currentTime() == pos {
			eventSink?(["event": "seekEnd"])
		} else {
			avPlayer.seek(to: pos, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
				if finished && self != nil {
					self!.eventSink?(["event": "seekEnd"])
					if self!.watcher == nil {
						self!.setPosition(time: self!.avPlayer.currentTime())
					}
				}
			}
		}
	}

	func setVolume(vol: Float) {
		volume = vol
		avPlayer.volume = volume
	}

	func setSpeed(spd: Float) {
		speed = spd
		if avPlayer.rate > 0 {
			avPlayer.rate = speed
		}
	}

	func setLooping(loop: Bool) {
		looping = loop
	}

	private func stopVideo() {
		if displayLink != nil {
#if os(macOS)
			CVDisplayLinkStop(displayLink!)
#else
			displayLink!.invalidate()
#endif
			displayLink = nil
		}
	}

	private func stopWatcher() {
		if watcher != nil {
			avPlayer.removeTimeObserver(watcher!)
			watcher = nil
		}
	}

	private func setPosition(time: CMTime) {
		if time != position {
			position = time
			eventSink?([
				"event": "position",
				"value": Int(position.seconds * 1000)
			])
		}
	}

	func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
		if let t = reading {
			reading = nil
			if let buffer = output?.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) {
				rendering = t
				return Unmanaged.passRetained(buffer)
			}
		}
		return nil
	}

	@objc private func onFinish(notification: NSNotification) {
		if state == 3 {
			if avPlayer.currentItem == nil || avPlayer.currentItem!.duration == .zero {
				if avPlayer.currentItem != nil {
					close()
				}
				eventSink?(["event": "finished"])
			} else {
				avPlayer.seek(to: .zero) { [weak self] finished in
				 if self != nil {
					 if self!.looping {
						 self!.play()
					 } else {
						 self!.state = 2
						 if finished {
							 self!.position = .zero
							 self!.bufferPosition = .zero
						 }
					 }
					 self!.eventSink?(["event": "finished"])
				 }
			 }
			}
		}
	}

	func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
		eventSink = events
		return nil
	}

	func onCancel(withArguments arguments: Any?) -> FlutterError? {
		eventSink = nil
		return nil
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		switch keyPath {
		case #keyPath(AVPlayer.timeControlStatus):
			if let oldValue = change?[NSKeyValueChangeKey.oldKey] as? Int,
				let oldStatus = AVPlayer.TimeControlStatus(rawValue: oldValue),
				oldStatus == .waitingToPlayAtSpecifiedRate || avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate {
				eventSink?([
					"event": "loading",
					"value": avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
				])
			}
		case #keyPath(AVPlayer.currentItem.status):
			switch avPlayer.currentItem?.status {
			case .readyToPlay:
				avPlayer.volume = volume
				state = 2
				eventSink?([
					"event": "mediaInfo",
					"duration": avPlayer.currentItem!.duration.seconds > 0 ? Int(avPlayer.currentItem!.duration.seconds * 1000) : 0,
					"source": source!
				])
			case .failed:
				if state > 0 {
					eventSink?([
						"event": "error",
						"value": avPlayer.currentItem?.error?.localizedDescription ?? "Unknown error"
					])
					close()
				}
			default:
				break
			}
		case #keyPath(AVPlayer.currentItem.presentationSize):
			if let width = avPlayer.currentItem?.presentationSize.width,
				let height = avPlayer.currentItem?.presentationSize.height,
				state > 0 {
				if width == 0 || height == 0 {
					stopVideo()
				} else {
					if displayLink == nil {
						output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
						avPlayer.currentItem!.add(output!)
#if os(macOS)
						CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
						if displayLink != nil {
							CVDisplayLinkSetOutputCallback(displayLink!, { (displayLink, now, outputTime, flagsIn, flagsOut, context) -> CVReturn in
								let player: AvMediaPlayer = Unmanaged.fromOpaque(context!).takeUnretainedValue()
								player.displayCallback(outputTime: outputTime.pointee)
								return kCVReturnSuccess
							}, Unmanaged.passUnretained(self).toOpaque())
							CVDisplayLinkStart(displayLink!)
						}
#else
						displayLink = CADisplayLink(target: self, selector: #selector(displayCallback))
						displayLink!.add(to: .current, forMode: .common)
#endif
					}
				}
				eventSink?([
					"event": "videoSize",
					"width": width,
					"height": height
				])
			}
		case #keyPath(AVPlayer.currentItem.loadedTimeRanges):
			if let duration = avPlayer.currentItem?.duration.seconds,
				let currentTime = avPlayer.currentItem?.currentTime(),
				let timeRanges = avPlayer.currentItem?.loadedTimeRanges as? [CMTimeRange],
				state > 1 && duration > 0 {
				for timeRange in timeRanges {
					let end = timeRange.start + timeRange.duration
					if timeRange.start <= currentTime && end >= currentTime {
						if end != bufferPosition {
							bufferPosition = end
							eventSink?([
								"event": "buffer",
								"begin": Int(currentTime.seconds * 1000),
								"end": Int(bufferPosition.seconds * 1000)
							])
						}
						break
					}
				}
			}
		default:
			break
		}
	}
}

public class AvMediaPlayerPlugin: NSObject, FlutterPlugin {
	public static func register(with registrar: FlutterPluginRegistrar) {
#if os(macOS)
		let messager = registrar.messenger
#else
		let messager = registrar.messenger()
#endif
		registrar.addMethodCallDelegate(
			AvMediaPlayerPlugin(registrar: registrar),
			channel: FlutterMethodChannel(name: "av_media_player", binaryMessenger: messager)
		)
	}

	private var players: [Int64: AvMediaPlayer] = [:]
	private let registrar: FlutterPluginRegistrar

	init(registrar: FlutterPluginRegistrar) {
		self.registrar = registrar
		super.init()
	}

	public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
		for player in players.values {
			player.close()
		}
		players.removeAll()
	}

	public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
		switch call.method {
		case "create":
			let player = AvMediaPlayer(registrar: registrar)
			players[player.id] = player
			result(player.id)
		case "dispose":
			result(nil)
			if let id = call.arguments as? Int64 {
				players[id]?.close()
				players.removeValue(forKey: id)
			} else {
				detachFromEngine(for: registrar)
			}
		case "open":
			result(nil)
			if let args = call.arguments as? [String: Any],
				let id = args["id"] as? Int64,
				let value = args["value"] as? String {
				players[id]?.open(source: value)
			}
		case "close":
			result(nil)
			if let id = call.arguments as? Int64 {
				players[id]?.close()
			}
		case "play":
			result(nil)
			if let id = call.arguments as? Int64 {
				players[id]?.play()
			}
		case "pause":
			result(nil)
			if let id = call.arguments as? Int64 {
				players[id]?.pause()
			}
		case "seekTo":
			result(nil)
			if let args = call.arguments as? [String: Any],
				let id = args["id"] as? Int64,
				let value = args["value"] as? Double {
				players[id]?.seekTo(pos: CMTime(seconds: value / 1000, preferredTimescale: 1000))
			}
		case "setVolume":
			result(nil)
			if let args = call.arguments as? [String: Any],
				let id = args["id"] as? Int64,
				let value = args["value"] as? Float {
				players[id]?.setVolume(vol: value)
			}
		case "setSpeed":
			result(nil)
			if let args = call.arguments as? [String: Any],
				let id = args["id"] as? Int64,
				let value = args["value"] as? Float {
				players[id]?.setSpeed(spd: value)
			}
		case "setLooping":
			result(nil)
			if let args = call.arguments as? [String: Any],
				let id = args["id"] as? Int64,
				let value = args["value"] as? Bool {
				players[id]?.setLooping(loop: value)
			}
		default:
			result(FlutterMethodNotImplemented)
		}
	}
}
