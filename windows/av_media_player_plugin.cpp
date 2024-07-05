#include "include/av_media_player/av_media_player_plugin_c_api.h"
#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <d3d11.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.core.h>
#include <winrt/Windows.Media.Playback.h>
#include <DispatcherQueue.h>

using namespace std;
using namespace flutter;
using namespace winrt;
using namespace winrt::Windows::System;
using namespace winrt::Windows::Media::Core;
using namespace winrt::Windows::Media::Playback;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

class AvMediaPlayer : public enable_shared_from_this<AvMediaPlayer> {
	static ID3D11Device* d3dDevice;
	static DispatcherQueueController dispatcherController;
	static DispatcherQueue dispatcherQueue;

	EventChannel<EncodableValue>* eventChannel = nullptr;
	unique_ptr<EventSink<EncodableValue>> eventSink = nullptr;
	TextureVariant* texture = nullptr;
	TextureRegistrar* textureRegistrar = nullptr;
	FlutterDesktopGpuSurfaceDescriptor textureBuffer{};
	MediaPlayer mediaPlayer = MediaPlayer();
	IDirect3DSurface direct3DSurface;
	string source = "";
	uint8_t state = 0; //0: idle, 1: opening, 2: ready, 3: playing
	double volume = 1;
	double speed = 1;
	bool looping = false;
	int64_t position = 0;
	int64_t bufferPosition = 0;

	static void createDispatcherQueue() {
		check_hresult(CreateDispatcherQueueController(
			DispatcherQueueOptions{
				sizeof(DispatcherQueueOptions),
				DQTYPE_THREAD_CURRENT,
				DQTAT_COM_NONE
			},
			(PDISPATCHERQUEUECONTROLLER*)put_abi(dispatcherController)
		));
		dispatcherQueue = dispatcherController.DispatcherQueue();
	}

public:
	static void initGlobal() {
		//init_apartment(apartment_type::single_threaded);
		dispatcherQueue = DispatcherQueue::GetForCurrentThread();
		if (dispatcherQueue) {
			dispatcherQueue.ShutdownStarting([](auto, DispatcherQueueShutdownStartingEventArgs args) {
				args.GetDeferral().Complete();
				createDispatcherQueue();
			});
		} else {
			createDispatcherQueue();
		}
		com_ptr<ID3D11DeviceContext> d3dContext;
		D3D_FEATURE_LEVEL featureLevel{};
		check_hresult(D3D11CreateDevice(
			nullptr,
			D3D_DRIVER_TYPE_HARDWARE,
			nullptr,
			D3D11_CREATE_DEVICE_BGRA_SUPPORT,
			nullptr,
			0,
			D3D11_SDK_VERSION,
			&d3dDevice,
			&featureLevel,
			d3dContext.put()
		));
	}

	static void uninitGlobal() {
		if (d3dDevice) {
			d3dDevice->Release();
			d3dDevice = nullptr;
		}
		if (dispatcherController) {
			dispatcherController.ShutdownQueueAsync();
			dispatcherController = nullptr;
		}
		dispatcherQueue = nullptr;
		//uninit_apartment();
	}

	int64_t textureId = 0;

	AvMediaPlayer() {
		textureBuffer.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
		textureBuffer.format = kFlutterDesktopPixelFormatBGRA8888;
		mediaPlayer.IsVideoFrameServerEnabled(true);
		mediaPlayer.CommandManager().IsEnabled(false);
	}

	~AvMediaPlayer() {
		mediaPlayer.Close();
		if (textureRegistrar) {
			textureRegistrar->UnregisterTexture(textureId);
			delete texture;
		}
		if (direct3DSurface) {
			direct3DSurface.Close();
		}
		if (eventSink) {
			eventSink->EndOfStream();
		}
		if (eventChannel) {
			eventChannel->SetStreamHandler(nullptr);
			delete eventChannel;
		}
	}

	void init(PluginRegistrarWindows& registrar) {
		auto weakThis = weak_from_this();
		textureRegistrar = registrar.texture_registrar();
		texture = new TextureVariant(GpuSurfaceTexture(
			kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
			//kFlutterDesktopGpuSurfaceTypeD3d11Texture2D,
			[weakThis](auto, auto) -> const FlutterDesktopGpuSurfaceDescriptor* {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->textureBuffer.width > 0 && sharedThis->textureBuffer.height > 0) {
					if (!sharedThis->direct3DSurface || sharedThis->textureBuffer.width != sharedThis->textureBuffer.visible_width || sharedThis->textureBuffer.height != sharedThis->textureBuffer.visible_height) {
						sharedThis->textureBuffer.visible_width = sharedThis->textureBuffer.width;
						sharedThis->textureBuffer.visible_height = sharedThis->textureBuffer.height;
						D3D11_TEXTURE2D_DESC desc{
							(UINT)sharedThis->textureBuffer.width,
							(UINT)sharedThis->textureBuffer.height,
							1,
							1,
							DXGI_FORMAT_B8G8R8A8_UNORM,
							{ 1, DXGI_STANDARD_MULTISAMPLE_QUALITY_PATTERN },
							D3D11_USAGE_DEFAULT,
							D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE,
							0,
							D3D11_RESOURCE_MISC_SHARED
						};
						com_ptr<ID3D11Texture2D> d3d11Texture;
						check_hresult(sharedThis->d3dDevice->CreateTexture2D(&desc, nullptr, d3d11Texture.put()));
						//sharedThis->textureBuffer.handle = d3d11Texture.get();
						com_ptr<IDXGIResource> resource;
						d3d11Texture.as(resource);
						check_hresult(resource->GetSharedHandle(&sharedThis->textureBuffer.handle));
						com_ptr<IDXGISurface> dxgiSurface;
						d3d11Texture.as(dxgiSurface);
						if (sharedThis->direct3DSurface) {
							sharedThis->direct3DSurface.Close();
						}
						check_hresult(CreateDirect3D11SurfaceFromDXGISurface(dxgiSurface.get(), reinterpret_cast<IInspectable**>(put_abi(sharedThis->direct3DSurface))));
					}
					sharedThis->mediaPlayer.CopyFrameToVideoSurface(sharedThis->direct3DSurface);
					return &sharedThis->textureBuffer;
				}
				return nullptr;
			}
		));
		textureId = textureRegistrar->RegisterTexture(texture);
		char id[32];
		sprintf_s(id, "av_media_player/%lld", textureId);
		eventChannel = new EventChannel<EncodableValue>(
			registrar.messenger(),
			id,
			&StandardMethodCodec::GetInstance()
		);
		eventChannel->SetStreamHandler(make_unique<StreamHandlerFunctions<EncodableValue>>(
			[weakThis](const EncodableValue* arguments, unique_ptr<EventSink<EncodableValue>>&& events) {
				auto sharedThis = weakThis.lock();
				if (sharedThis) {
					sharedThis->eventSink = move(events);
				}
				return nullptr;
			},
			[weakThis](const EncodableValue* arguments) {
				auto sharedThis = weakThis.lock();
				if (sharedThis) {
					sharedThis->eventSink = nullptr;
				}
				return nullptr;
			}
		));
		auto playbackSession = mediaPlayer.PlaybackSession();

		playbackSession.NaturalVideoSizeChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, playbackSession]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 0) {
					sharedThis->textureBuffer.width = playbackSession.NaturalVideoWidth();
					sharedThis->textureBuffer.height = playbackSession.NaturalVideoHeight();
					if (sharedThis->eventSink) {
						sharedThis->eventSink->Success(EncodableMap{
							{ EncodableValue("event"), EncodableValue("videoSize") },
							{ EncodableValue("width"), EncodableValue((double)sharedThis->textureBuffer.width) },
							{ EncodableValue("height"), EncodableValue((double)sharedThis->textureBuffer.height) }
						});
					}
				}
			}));
		});

		playbackSession.PositionChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, playbackSession]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 1 && !sharedThis->mediaPlayer.RealTimePlayback()) {
					auto position = playbackSession.Position().count() / 10000;
					if (position != sharedThis->position) {
						sharedThis->position = position;
						if (sharedThis->eventSink) {
							sharedThis->eventSink->Success(EncodableMap{
								{ EncodableValue("event"), EncodableValue("position") },
								{ EncodableValue("value"), EncodableValue(sharedThis->position) }
							});
						}
					}
				}
			}));
		});

		playbackSession.SeekCompleted([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 1 && sharedThis->eventSink) {
					sharedThis->eventSink->Success(EncodableMap{
						{ EncodableValue("event"), EncodableValue("seekEnd") }
					});
				}
			}));
		});

		playbackSession.BufferingStarted([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 2 && sharedThis->eventSink) {
					sharedThis->eventSink->Success(EncodableMap{
						{ EncodableValue("event"), EncodableValue("loading") },
						{ EncodableValue("value"), EncodableValue(true) }
					});
				}
			}));
		});

		playbackSession.BufferingEnded([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 2 && sharedThis->eventSink) {
					sharedThis->eventSink->Success(EncodableMap{
						{ EncodableValue("event"), EncodableValue("loading") },
						{ EncodableValue("value"), EncodableValue(false) }
					});
				}
			}));
		});

		playbackSession.BufferedRangesChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, playbackSession]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 1 && !sharedThis->mediaPlayer.RealTimePlayback()) {
					auto buffered = playbackSession.GetBufferedRanges();
					for (uint32_t i = 0; i < buffered.Size(); i++) {
						auto start = buffered.GetAt(i).Start.count();
						auto end = buffered.GetAt(i).End.count();
						auto pos = playbackSession.Position().count();
						if (start <= pos && end >= pos) {
							int64_t t = end / 10000;
							if (sharedThis->bufferPosition != t) {
								sharedThis->bufferPosition = t;
								if (sharedThis->eventSink) {
									sharedThis->eventSink->Success(EncodableMap{
										{ EncodableValue("event"), EncodableValue("buffer") },
										{ EncodableValue("begin"), EncodableValue(pos / 10000) },
										{ EncodableValue("end"), EncodableValue(sharedThis->bufferPosition) }
									});
								}
							}
							break;
						}
					}
				}
			}));
		});

		mediaPlayer.VideoFrameAvailable([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis) {
				sharedThis->textureRegistrar->MarkTextureFrameAvailable(sharedThis->textureId);
			}
		});

		mediaPlayer.MediaFailed([weakThis](auto, MediaPlayerFailedEventArgs const& reason) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, reason]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 0) {
					sharedThis->close();
					if (sharedThis->eventSink) {
						EncodableValue message;
						switch (reason.Error()) {
						case MediaPlayerError::Aborted:
							message = EncodableValue("Aborted");
							break;
						case MediaPlayerError::NetworkError:
							message = EncodableValue("NetworkError");
							break;
						case MediaPlayerError::DecodingError:
							message = EncodableValue("DecodingError");
							break;
						case MediaPlayerError::SourceNotSupported:
							message = EncodableValue("SourceNotSupported");
							break;
						default:
							message = EncodableValue("Unknown");
							break;
						}
						sharedThis->eventSink->Success(EncodableMap{
							{ EncodableValue("event"), EncodableValue("error") },
							{ EncodableValue("value"), message }
						});
					}
				}
			}));
		});

		mediaPlayer.MediaOpened([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state == 1) {
					auto playbackSession = sharedThis->mediaPlayer.PlaybackSession();
					sharedThis->state = 2;
					sharedThis->mediaPlayer.Volume(sharedThis->volume);
					playbackSession.PlaybackRate(sharedThis->speed);
					auto duration = playbackSession.NaturalDuration().count();
					if (duration == INT64_MAX) {
						duration = 0;
					}
					sharedThis->mediaPlayer.RealTimePlayback(duration == 0);
					if (sharedThis->eventSink) {
						sharedThis->eventSink->Success(EncodableMap{
							{ EncodableValue("event"), EncodableValue("mediaInfo") },
							{ EncodableValue("duration"), EncodableValue(duration / 10000) },
							{ EncodableValue("source"), EncodableValue(sharedThis->source) }
						});
					}
				}
			}));
		});
		 
		mediaPlayer.MediaEnded([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 2) {
					if (sharedThis->mediaPlayer.RealTimePlayback()) {
						sharedThis->close();
					} else if (sharedThis->looping) {
						sharedThis->mediaPlayer.Play();
					} else {
						sharedThis->state = 2;
					}
					if (sharedThis->eventSink) {
						sharedThis->eventSink->Success(EncodableMap{
							{ EncodableValue("event"), EncodableValue("finished") }
						});
					}
				}
			}));
		});
	}

	void open(const string& src) {
		hstring url;
		if (src._Starts_with("asset://")) {
			wchar_t path[MAX_PATH];
			GetModuleFileNameW(nullptr, path, MAX_PATH);
			wstring sourceUrl(L"file://");
			sourceUrl += path;
			sourceUrl.replace(sourceUrl.find_last_of(L'\\') + 1, sourceUrl.length(), L"data/flutter_assets/");
			sourceUrl += wstring(src.begin() + 8, src.end());
			replace(sourceUrl.begin(), sourceUrl.end(), L'\\', L'/');
			url = sourceUrl;
		} else if (src.find("://") != string::npos) {
			url = to_hstring(src);
		} else {
			wstring sourceUrl(L"file://");
			sourceUrl += wstring(src.begin(), src.end());
			replace(sourceUrl.begin(), sourceUrl.end(), L'\\', L'/');
			url = sourceUrl;
		}
		close();
		source = src;
		state = 1;
		mediaPlayer.Source(MediaSource::CreateFromUri(winrt::Windows::Foundation::Uri(url)));
	}

	void close() {
		state = 0;
		textureBuffer.width = textureBuffer.height = 0;
		if (direct3DSurface) {
			direct3DSurface.Close();
			direct3DSurface = nullptr;
		}
		position = 0;
		bufferPosition = 0;
		source = "";
		auto src = mediaPlayer.Source();
		if (src) {
			mediaPlayer.Source(nullptr);
			src.as<MediaSource>().Close();
		}
	}

	void play() {
		if (state == 2) {
			state = 3;
			mediaPlayer.Play();
		}
	}

	void pause() {
		if (state > 2) {
			state = 2;
			mediaPlayer.Pause();
		}
	}

	void seekTo(int64_t pos) {
		auto playbackSession = mediaPlayer.PlaybackSession();
		if (eventSink && (!mediaPlayer.Source() || mediaPlayer.RealTimePlayback() || playbackSession.Position().count() / 10000 == pos)) {
			eventSink->Success(EncodableValue(EncodableMap{
				{EncodableValue("event"), EncodableValue("seekEnd")}
			}));
		} else if (state > 1) {
			playbackSession.Position(chrono::milliseconds(pos));
		}
	}

	void setVolume(double vol) {
		volume = vol;
		mediaPlayer.Volume(vol);
	}

	void setSpeed(double spd) {
		speed = spd;
		mediaPlayer.PlaybackSession().PlaybackRate(speed);
	}

	void setLooping(bool loop) {
		looping = loop;
	}
};
ID3D11Device* AvMediaPlayer::d3dDevice = nullptr;
DispatcherQueueController AvMediaPlayer::dispatcherController{ nullptr };
DispatcherQueue AvMediaPlayer::dispatcherQueue{ nullptr };

class AvMediaPlayerPlugin : public Plugin {
	MethodChannel<EncodableValue>* methodChannel;
	map<int64_t, shared_ptr<AvMediaPlayer>> players;
	EncodableValue Id = EncodableValue("id");
	EncodableValue Value = EncodableValue("value");

public:
	AvMediaPlayerPlugin(PluginRegistrarWindows& registrar) {
		AvMediaPlayer::initGlobal();
		methodChannel = new MethodChannel<EncodableValue>(
			registrar.messenger(),
			"av_media_player",
			&StandardMethodCodec::GetInstance()
		);

		methodChannel->SetMethodCallHandler([&](const MethodCall<EncodableValue>& call, unique_ptr<MethodResult<EncodableValue>> result) {
			auto returned = false;
			auto& methodName = call.method_name();
			if (methodName == "create") {
				auto player = make_shared<AvMediaPlayer>();
				player->init(registrar);
				players[player->textureId] = player;
				result->Success(EncodableValue(player->textureId));
				returned = true;
			} else if (methodName == "dispose") {
				if (call.arguments()->IsNull()) {
					players.clear();
				} else {
					players.erase(call.arguments()->LongValue());
				}
			} else if (methodName == "open") {
				auto& args = get<EncodableMap>(*call.arguments());
				players[args.at(Id).LongValue()]->open(get<string>(args.at(Value)));
			} else if (methodName == "close") {
				players[call.arguments()->LongValue()]->close();
			} else if (methodName == "play") {
				players[call.arguments()->LongValue()]->play();
			} else if (methodName == "pause") {
				players[call.arguments()->LongValue()]->pause();
			} else if (methodName == "seekTo") {
				auto& args = get<EncodableMap>(*call.arguments());
				players[args.at(Id).LongValue()]->seekTo(args.at(Value).LongValue());
			} else if (methodName == "setVolume") {
				auto& args = get<EncodableMap>(*call.arguments());
				players[args.at(Id).LongValue()]->setVolume(get<double>(args.at(Value)));
			} else if (methodName == "setSpeed") {
				auto& args = get<EncodableMap>(*call.arguments());
				players[args.at(Id).LongValue()]->setSpeed(get<double>(args.at(Value)));
			} else if (methodName == "setLooping") {
				auto& args = get<EncodableMap>(*call.arguments());
				players[args.at(Id).LongValue()]->setLooping(get<bool>(args.at(Value)));
			} else {
				result->NotImplemented();
				returned = true;
			}
			if (!returned) {
				result->Success();
			}
		});
	}

	virtual ~AvMediaPlayerPlugin() {
		players.clear();
		methodChannel->SetMethodCallHandler(nullptr);
		delete methodChannel;
		AvMediaPlayer::uninitGlobal();
	}

	AvMediaPlayerPlugin(const AvMediaPlayerPlugin&) = delete;
	AvMediaPlayerPlugin& operator=(const AvMediaPlayerPlugin&) = delete;
};

void AvMediaPlayerPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrarRef) {
	auto& registrar = *PluginRegistrarManager::GetInstance()->GetRegistrar<PluginRegistrarWindows>(registrarRef);
	registrar.AddPlugin(make_unique<AvMediaPlayerPlugin>(registrar));
}