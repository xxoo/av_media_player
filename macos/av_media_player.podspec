#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint av_media_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'av_media_player'
  s.version          = '1.1.1'
  s.summary          = 'A lightweight media player for flutter.'
  s.description      = <<-DESC
A lightweight Flutter media player with subtitle rendering and track selection, leveraging system components for seamless playback and video rendering via Flutter's Texture widget.
                       DESC
  s.homepage         = 'http://github.com/xxoo/av_media_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'xxoo' => 'http://github.com/xxoo' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
