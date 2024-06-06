#include "include/av_media_player/av_media_player_plugin_c_api.h"
#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <d3d11.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <dispatcherqueue.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.core.h>
#include <winrt/Windows.Media.Playback.h>

using namespace std;
using namespace flutter;
using namespace winrt;
using namespace winrt::Windows::System;
using namespace winrt::Windows::Media::Core;
using namespace winrt::Windows::Media::Playback;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

class AvMediaPlayer : public enable_shared_from_this<AvMediaPlayer> {
	static ID3D11Device* d3dDevice;
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

	// Helper function to post a message to the Flutter UI thread.
	void postMessage(const EncodableValue& message) {
		dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis = weak_from_this(), message]() {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->eventSink.get() != nullptr) {
				sharedThis->eventSink->Success(message);
			}
		}));
	}

public:
	static void initGlobal() {
		//init_apartment(apartment_type::single_threaded);
		DispatcherQueueController dispatcherController{ nullptr };
		check_hresult(CreateDispatcherQueueController(
			DispatcherQueueOptions{
				sizeof(DispatcherQueueOptions),
				DQTYPE_THREAD_CURRENT,
				DQTAT_COM_NONE
			},
			(PDISPATCHERQUEUECONTROLLER*)put_abi(dispatcherController)
		));
		dispatcherQueue = dispatcherController.DispatcherQueue();
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
		if (d3dDevice != nullptr) {
			d3dDevice->Release();
			d3dDevice = nullptr;
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
		if (textureRegistrar != nullptr) {
			textureRegistrar->UnregisterTexture(textureId);
			delete texture;
		}
		if (eventSink != nullptr) {
			eventSink->EndOfStream();
		}
		if (eventChannel != nullptr) {
			eventChannel->SetStreamHandler(nullptr);
			delete eventChannel;
		}
	}

	void init(PluginRegistrarWindows* registrar) {
		auto weakThis = weak_from_this();
		textureRegistrar = registrar->texture_registrar();
		texture = new TextureVariant(GpuSurfaceTexture(
			kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
			//kFlutterDesktopGpuSurfaceTypeD3d11Texture2D,
			[weakThis](auto, auto) -> const FlutterDesktopGpuSurfaceDescriptor* {
				auto sharedThis = weakThis.lock();
				if (sharedThis != nullptr && sharedThis->direct3DSurface != nullptr) {
					sharedThis->mediaPlayer.CopyFrameToVideoSurface(sharedThis->direct3DSurface);
					return &sharedThis->textureBuffer;
				} else {
					return nullptr;
				}
			}
		));
		textureId = textureRegistrar->RegisterTexture(texture);
		char id[32];
		sprintf_s(id, "av_media_player/%lld", textureId);
		eventChannel = new EventChannel<EncodableValue>(
			registrar->messenger(),
			id,
			&StandardMethodCodec::GetInstance()
		);
		eventChannel->SetStreamHandler(make_unique<StreamHandlerFunctions<EncodableValue>>(
			[weakThis](const EncodableValue* arguments, unique_ptr<EventSink<EncodableValue>>&& events) {
				auto sharedThis = weakThis.lock();
				if (sharedThis != nullptr) {
					sharedThis->eventSink = move(events);
				}
				return nullptr;
			},
			[weakThis](const EncodableValue* arguments) {
				auto sharedThis = weakThis.lock();
				if (sharedThis != nullptr) {
					sharedThis->eventSink = nullptr;
				}
				return nullptr;
			}
		));
		auto playbackSession = mediaPlayer.PlaybackSession();

		playbackSession.NaturalVideoSizeChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state > 0) {
				sharedThis->textureBuffer.visible_width = playbackSession.NaturalVideoWidth();
				sharedThis->textureBuffer.visible_height = playbackSession.NaturalVideoHeight();
				if (sharedThis->textureBuffer.width != sharedThis->textureBuffer.visible_width || sharedThis->textureBuffer.height != sharedThis->textureBuffer.visible_height) {
					sharedThis->textureBuffer.width = sharedThis->textureBuffer.visible_width;
					sharedThis->textureBuffer.height = sharedThis->textureBuffer.visible_height;
					if (sharedThis->textureBuffer.width > 0 && sharedThis->textureBuffer.height > 0) {
						D3D11_TEXTURE2D_DESC desc = {};
						desc.ArraySize = 1;
						desc.CPUAccessFlags = 0;
						desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
						desc.MipLevels = 1;
						desc.SampleDesc.Count = 1;
						desc.SampleDesc.Quality = DXGI_STANDARD_MULTISAMPLE_QUALITY_PATTERN;
						desc.Usage = D3D11_USAGE_DEFAULT;
						desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
						desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
						desc.Width = (UINT)sharedThis->textureBuffer.width;
						desc.Height = (UINT)sharedThis->textureBuffer.height;
						com_ptr<ID3D11Texture2D> d3d11Texture;
						check_hresult(sharedThis->d3dDevice->CreateTexture2D(&desc, nullptr, d3d11Texture.put()));
						//sharedThis->textureBuffer.handle = d3d11Texture.get();
						com_ptr<IDXGIResource> resource;
						d3d11Texture.as(resource);
						check_hresult(resource->GetSharedHandle(&sharedThis->textureBuffer.handle));
						com_ptr<IDXGISurface> dxgiSurface;
						d3d11Texture.as(dxgiSurface);
						check_hresult(CreateDirect3D11SurfaceFromDXGISurface(dxgiSurface.get(), reinterpret_cast<IInspectable**>(put_abi(sharedThis->direct3DSurface))));
					} else {
						sharedThis->textureBuffer.handle = nullptr;
						sharedThis->direct3DSurface = nullptr;
					}
					sharedThis->postMessage(EncodableValue(EncodableMap{
						{ EncodableValue("event"), EncodableValue("videoSize") },
						{ EncodableValue("width"), EncodableValue((double)sharedThis->textureBuffer.width) },
						{ EncodableValue("height"), EncodableValue((double)sharedThis->textureBuffer.height) }
					}));
				}
			}
		});

		playbackSession.PositionChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && !sharedThis->mediaPlayer.RealTimePlayback()) {
				auto position = playbackSession.Position().count() / 10000;
				if (position != sharedThis->position) {
					sharedThis->position = position;
					sharedThis->postMessage(EncodableValue(EncodableMap{
						{ EncodableValue("event"), EncodableValue("position") },
						{ EncodableValue("value"), EncodableValue(sharedThis->position) }
					}));
				}
			}
		});

		playbackSession.SeekCompleted([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state > 1) {
				sharedThis->postMessage(EncodableValue(EncodableMap{
					{ EncodableValue("event"), EncodableValue("seekEnd") }
				}));
			}
		});

		playbackSession.BufferingStarted([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state > 1) {
				sharedThis->postMessage(EncodableValue(EncodableMap{
					{ EncodableValue("event"), EncodableValue("loading") },
					{ EncodableValue("value"), EncodableValue(true) }
				}));
			}
		});

		playbackSession.BufferingEnded([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state > 1) {
				sharedThis->postMessage(EncodableValue(EncodableMap{
					{ EncodableValue("event"), EncodableValue("loading") },
					{ EncodableValue("value"), EncodableValue(false) }
				}));
			}
		});

		playbackSession.BufferedRangesChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state > 1 && !sharedThis->mediaPlayer.RealTimePlayback()) {
				auto buffered = playbackSession.GetBufferedRanges();
				for (uint32_t i = 0; i < buffered.Size(); i++) {
					auto start = buffered.GetAt(i).Start.count();
					auto end = buffered.GetAt(i).End.count();
					auto pos = playbackSession.Position().count();
					if (start <= pos && end >= pos) {
						int64_t t = end / 10000;
						if (sharedThis->bufferPosition != t) {
							sharedThis->bufferPosition = t;
							sharedThis->postMessage(EncodableValue(EncodableMap{
								{ EncodableValue("event"), EncodableValue("buffer") },
								{ EncodableValue("begin"), EncodableValue(pos / 10000) },
								{ EncodableValue("end"), EncodableValue(sharedThis->bufferPosition) }
							}));
						}
						break;
					}
				}
			}
		});

		mediaPlayer.VideoFrameAvailable([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->direct3DSurface != nullptr) {
				sharedThis->textureRegistrar->MarkTextureFrameAvailable(sharedThis->textureId);
			}
		});

		mediaPlayer.MediaFailed([weakThis](auto, MediaPlayerFailedEventArgs const& reason) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state > 0) {
				sharedThis->close();
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
				sharedThis->postMessage(EncodableValue(EncodableMap{
					{ EncodableValue("event"), EncodableValue("error") },
					{ EncodableValue("value"), message }
				}));
			}
		});

		mediaPlayer.MediaOpened([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state == 1) {
				auto playbackSession = sharedThis->mediaPlayer.PlaybackSession();
				sharedThis->state = 2;
				sharedThis->mediaPlayer.Volume(sharedThis->volume);
				playbackSession.PlaybackRate(sharedThis->speed);
				auto duration = playbackSession.NaturalDuration().count();
				if (duration == INT64_MAX) {
					duration = 0;
				}
				sharedThis->mediaPlayer.RealTimePlayback(duration == 0);
				sharedThis->postMessage(EncodableValue(EncodableMap{
					{ EncodableValue("event"), EncodableValue("mediaInfo") },
					{ EncodableValue("duration"), EncodableValue(duration / 10000) },
					{ EncodableValue("source"), EncodableValue(sharedThis->source) }
				}));
			}
		});

		mediaPlayer.MediaEnded([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis != nullptr && sharedThis->state == 3) {
				if (sharedThis->mediaPlayer.RealTimePlayback()) {
					sharedThis->close();
				} else if (sharedThis->looping) {
					sharedThis->mediaPlayer.Play();
				} else {
					sharedThis->state = 2;
					sharedThis->position = 0;
					sharedThis->bufferPosition = 0;
				}
				sharedThis->postMessage(EncodableValue(EncodableMap{
					{ EncodableValue("event"), EncodableValue("finished") }
				}));
			}
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
		textureBuffer.width = textureBuffer.height = textureBuffer.visible_width = textureBuffer.visible_height = 0;
		textureBuffer.handle = nullptr;
		direct3DSurface = nullptr;
		position = 0;
		bufferPosition = 0;
		source = "";
		auto src = mediaPlayer.Source();
		if (src != nullptr) {
			mediaPlayer.Source(nullptr);
			src.as<MediaSource>().Close();
		}
	}

	void play() {
		if (state > 1) {
			state = 3;
			mediaPlayer.Play();
		}
	}

	void pause() {
		if (state == 3) {
			state = 2;
			mediaPlayer.Pause();
		}
	}

	void seekTo(int64_t pos) {
		auto playbackSession = mediaPlayer.PlaybackSession();
		if (eventSink != nullptr && (mediaPlayer.Source() == nullptr || mediaPlayer.RealTimePlayback() || playbackSession.Position().count() / 10000 == pos)) {
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
DispatcherQueue AvMediaPlayer::dispatcherQueue{ nullptr };

class AvMediaPlayerPlugin : public Plugin {
	MethodChannel<EncodableValue>* methodChannel;
	map<int64_t, shared_ptr<AvMediaPlayer>> players;
	EncodableValue Id = EncodableValue("id");
	EncodableValue Value = EncodableValue("value");
	EncodableValue Null = EncodableValue(monostate{});

public:
	AvMediaPlayerPlugin(PluginRegistrarWindows* registrar) {
		AvMediaPlayer::initGlobal();
		methodChannel = new MethodChannel<EncodableValue>(
			registrar->messenger(),
			"av_media_player",
			&StandardMethodCodec::GetInstance()
		);

		methodChannel->SetMethodCallHandler([&, registrar](const MethodCall<EncodableValue>& call, unique_ptr<MethodResult<EncodableValue>> result) {
			auto& methodName = call.method_name();
			if (methodName == "create") {
				auto player = make_shared<AvMediaPlayer>();
				player->init(registrar);
				players[player->textureId] = player;
				result->Success(EncodableValue(player->textureId));
			} else if (methodName == "dispose") {
				result->Success(Null);
				auto id = call.arguments()->LongValue();
				if (id < 0) {
					players.clear();
				} else {
					players.erase(id);
				}
			} else if (methodName == "open") {
				result->Success(Null);
				auto& args = get<EncodableMap>(*call.arguments());
				auto& value = get<string>(args.at(Value));
				auto id = args.at(Id).LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->open(value);
				}
			} else if (methodName == "close") {
				result->Success(Null);
				auto id = call.arguments()->LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->close();
				}
			} else if (methodName == "play") {
				result->Success(Null);
				auto id = call.arguments()->LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->play();
				}
			} else if (methodName == "pause") {
				result->Success(Null);
				auto id = call.arguments()->LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->pause();
				}
			} else if (methodName == "seekTo") {
				result->Success(Null);
				auto& args = get<EncodableMap>(*call.arguments());
				auto value = args.at(Value).LongValue();
				auto id = args.at(Id).LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->seekTo(value);
				}
			} else if (methodName == "setVolume") {
				result->Success(Null);
				auto& args = get<EncodableMap>(*call.arguments());
				auto value = get<double>(args.at(Value));
				auto id = args.at(Id).LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->setVolume(value);
				}
			} else if (methodName == "setSpeed") {
				result->Success(Null);
				auto& args = get<EncodableMap>(*call.arguments());
				auto value = get<double>(args.at(Value));
				auto id = args.at(Id).LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->setSpeed(value);
				}
			} else if (methodName == "setLooping") {
				result->Success(Null);
				auto& args = get<EncodableMap>(*call.arguments());
				auto value = get<bool>(args.at(Value));
				auto id = args.at(Id).LongValue();
				auto& player = players[id];
				if (player != nullptr) {
					player->setLooping(value);
				}
			} else {
				result->NotImplemented();
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
	auto registrar = PluginRegistrarManager::GetInstance()->GetRegistrar<PluginRegistrarWindows>(registrarRef);
	registrar->AddPlugin(make_unique<AvMediaPlayerPlugin>(registrar));
}