#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_leap_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_leap_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Flutter package for Liquid AI\'s LEAP SDK - Deploy small language models on mobile devices'
  s.description      = <<-DESC
  A Flutter plugin for integrating Liquid AI's LEAP SDK, enabling on-device deployment of small language models in Flutter applications.
                       DESC
  s.homepage         = 'https://github.com/mbadyl/flutter_leap_sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mikolaj Badyl' => 'mikolajbady0@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' 
  }
  s.swift_version = '5.9'
  
  # LEAP SDK dependency
  s.dependency 'Leap-SDK', '~> 0.4.0'
end