#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint av_media_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'av_media_player'
  s.version          = '0.6.4'
  s.summary          = 'A lightweight media player for flutter.'
  s.description      = <<-DESC
A lightweight media player for flutter. Which uses Texture Widget for video rendering. Backend builts on AVPlayer(ios/macos) and MediaPlayer(Android).
                       DESC
  s.homepage         = 'http://github.com/xxoo/av_media_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'xxoo' => 'http://github.com/xxoo' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
