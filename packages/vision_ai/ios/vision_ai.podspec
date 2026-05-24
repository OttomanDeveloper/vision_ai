Pod::Spec.new do |s|
  s.name             = 'vision_ai'
  s.version          = '0.1.0'
  s.summary          = 'On-device hand gesture recognition and facial emotion detection.'
  s.description      = 'Flutter plugin for real-time hand gesture recognition (MediaPipe) and facial emotion detection (ML Kit + TFLite). Runs entirely on-device.'
  s.homepage         = 'https://github.com/OttomanDeveloper/vision_ai'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'OttomanDeveloper' => 'bradsimon109@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.resource_bundles  = { 'vision_ai_assets' => ['Assets/**'] }
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'

  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision', '~> 0.10'
  s.dependency 'GoogleMLKit/FaceDetection', '~> 8.0'
  s.dependency 'TensorFlowLiteSwift', '~> 2.14'

  # Flutter.framework does not contain a i386 slice
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
