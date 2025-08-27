# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2025-01-27

### Added
- ✨ **Function Calling Support**: Complete implementation of function calling for conversations with streaming support
- 🖼️ **Vision Model Streaming**: Added streaming support for vision models on both iOS and Android platforms
- 🔧 **Enhanced Debug Logging**: Comprehensive debug logging for function execution and streaming workflows

### Fixed
- 🐛 **Function Execution**: Fixed type casting errors in function argument processing
- 🔄 **Android Vision Streaming**: Resolved compilation errors in Android Kotlin implementation
- 📱 **UI Streaming Updates**: Fixed UI not updating during vision model streaming responses
- 🏗️ **iOS Event Handling**: Improved iOS event sink handling for reliable streaming

### Changed
- 🎨 **Example App UI**: Updated example app with screen titles and improved button layout
- 📝 **Function Calling Tab**: Simplified streaming logic to match Regular Chat tab behavior
- 🔄 **Streaming Architecture**: Unified streaming approach across all chat modes

## [0.2.1] - 2025-01-20

### Added
- Initial release with basic text generation support
- Model downloading and management
- Conversation management
- Basic streaming support

### Fixed
- Initial stability improvements

## [0.2.0] - 2025-01-15

### Added
- First public release of Flutter LEAP SDK
- Support for LFM2 models (350M, 700M, 1.2B parameters)
- Cross-platform support (iOS and Android)
- Model downloading with progress tracking
- Basic conversation management