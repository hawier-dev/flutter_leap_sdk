# Flutter LEAP SDK

A Flutter plugin for integrating Liquid AI's LEAP SDK, enabling on-device deployment of small language models in Flutter applications.

## Platform Support

| Platform | Status | Notes |
|----------|--------|--------|
| Android  | ✅ Fully Supported | API 31+, arm64-v8a, extensively tested |
| iOS      | ⚠️  Supported | iOS 15+, 64-bit architecture, **not 100% tested** |

## Features

- ✅ **Model Management**: Download, load, unload, and delete models
- ✅ **Progress Tracking**: Real-time download progress with throttling
- ✅ **Text Generation**: Both blocking and streaming responses
- ✅ **Conversation Support**: Persistent conversation history and context
- ✅ **Function Calling**: Register and execute custom functions (experimental)
- ✅ **Error Handling**: Comprehensive exception system with detailed error codes
- ✅ **Memory Management**: Efficient model lifecycle with cleanup
- ✅ **Built on Official LEAP SDK**: Uses Liquid AI's native SDK (v0.4.0)
- ✅ **Secure Logging**: Production-safe logging system with sensitive data protection

## Getting Started

### Prerequisites

- Flutter SDK
- **Android**: Device with `arm64-v8a` ABI, minimum API level 31
- **iOS**: Device with iOS 15+, 64-bit architecture (iPhone 6s and newer)
- 3GB+ RAM recommended for model execution

### Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_leap_sdk: ^0.1.0
```

## Usage

### Basic Usage

```dart
import 'package:flutter_leap_sdk/flutter_leap_sdk.dart';

// Download a model (using display name for convenience)
await FlutterLeapSdkService.downloadModel(
  modelName: 'LFM2-350M', // Display name or full filename
  onProgress: (progress) => print('Download: ${progress.percentage}%'),
);

// Load the model (supports display names)
await FlutterLeapSdkService.loadModel(
  modelPath: 'LFM2-350M', // Will resolve to full filename automatically
);

// Generate response
String response = await FlutterLeapSdkService.generateResponse(
  'Hello, AI!',
  systemPrompt: 'You are a helpful assistant.',
);
print(response);

// Or use streaming for real-time responses
FlutterLeapSdkService.generateResponseStream('Hello, AI!').listen(
  (chunk) => print('Chunk: $chunk'),
  onDone: () => print('Generation complete'),
  onError: (error) => print('Error: $error'),
);
```

### Available Models

All models are downloaded from Hugging Face and cached locally:

| Model | Size | Description | Use Case |
|-------|------|-------------|----------|
| **LFM2-350M** | 322 MB | Smallest model | Basic chat, simple tasks, testing |
| **LFM2-700M** | 610 MB | Balanced model | General purpose, good performance/size ratio |
| **LFM2-1.2B** | 924 MB | Largest model | Best quality, complex reasoning tasks |

> **Note**: Models are automatically downloaded to the app's documents directory under `/leap/` folder.

### Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_leap_sdk/flutter_leap_sdk.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool isModelLoaded = false;
  String response = '';

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      // Check if model exists, download if not
      bool exists = await FlutterLeapSdkService.checkModelExists(
        'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle'
      );
      
      if (!exists) {
        await FlutterLeapSdkService.downloadModel(
          modelName: 'LFM2-350M', // Using display name for convenience
          onProgress: (progress) {
            print('Download progress: ${progress.percentage}%');
            // Progress includes: bytesDownloaded, totalBytes, percentage
          },
        );
      }

      // Load the model with options
      await FlutterLeapSdkService.loadModel(
        modelPath: 'LFM2-350M',
        options: ModelLoadingOptions(
          randomSeed: 42,
          cpuThreads: 4,
        ),
      );
      
      setState(() {
        isModelLoaded = true;
      });
    } catch (e) {
      print('Error initializing model: $e');
    }
  }

  Future<void> _generateResponse(String message) async {
    if (!isModelLoaded) return;
    
    setState(() {
      response = '';
    });

    try {
      // Use streaming for real-time response
      FlutterLeapSdkService.generateResponseStream(message).listen(
        (chunk) {
          setState(() {
            response += chunk;
          });
        },
      );
    } catch (e) {
      print('Error generating response: $e');
    }
  }
}
```

## Advanced Usage

### Conversation Management

```dart
// Create a persistent conversation
Conversation conversation = await FlutterLeapSdkService.createConversation(
  systemPrompt: 'You are a helpful coding assistant.',
  generationOptions: GenerationOptions(
    temperature: 0.7,
    maxTokens: 1000,
  ),
);

// Generate responses within conversation context
String response = await conversation.generateResponse('Explain async/await in Dart');

// Use streaming with conversation
conversation.generateResponseStream('What are futures?').listen(
  (chunk) => print(chunk),
);

// Conversation automatically maintains history
print('History: ${conversation.history.length} messages');
```

### Error Handling

```dart
try {
  await FlutterLeapSdkService.loadModel(modelPath: 'nonexistent-model');
} on ModelLoadingException catch (e) {
  print('Failed to load model: ${e.message} (${e.code})');
} on ModelNotLoadedException catch (e) {
  print('Model not loaded: ${e.message}');
} on FlutterLeapSdkException catch (e) {
  print('SDK error: ${e.message} (${e.code})');
}
```

## API Reference

### FlutterLeapSdkService

#### Model Management
- `loadModel({String? modelPath, ModelLoadingOptions? options})` - Load model with options
- `unloadModel()` - Unload current model and free memory
- `checkModelLoaded()` - Check if model is loaded
- `checkModelExists(String modelName)` - Check if model file exists
- `getDownloadedModels()` - List all local models
- `deleteModel(String fileName)` - Delete model file
- `getModelInfo(String fileName)` - Get model metadata

#### Text Generation
- `generateResponse(String message, {String? systemPrompt, GenerationOptions? options})` - Generate complete response
- `generateResponseStream(String message, {String? systemPrompt, GenerationOptions? options})` - Streaming generation
- `cancelStreaming()` - Cancel active streaming

#### Conversation Management
- `createConversation({String? systemPrompt, GenerationOptions? options})` - Create conversation
- `getConversation(String id)` - Get existing conversation
- `disposeConversation(String id)` - Clean up conversation resources

#### Download Management
- `downloadModel({String? modelUrl, String? modelName, Function(DownloadProgress)? onProgress})` - Download with progress
- `cancelDownload(String downloadId)` - Cancel ongoing download
- `getActiveDownloads()` - List active download IDs

## Additional Information

This package is built on top of Liquid AI's official LEAP SDK. For more information about LEAP SDK and Liquid AI, visit [leap.liquid.ai](https://leap.liquid.ai).

### iOS Implementation Status

⚠️ **Important**: iOS support is implemented but **not 100% tested** in production environments.

**What's implemented:**
- ✅ Complete Flutter-iOS bridge
- ✅ Native LEAP SDK integration (v0.4.0)
- ✅ Model loading and management
- ✅ Text generation (blocking and streaming)
- ✅ CocoaPods integration with `Leap-SDK`
- ✅ iOS 15+ and Swift 5.9+ support

**Testing status:**
- ✅ Android: Extensively tested in production
- ⚠️ iOS: Basic functionality verified, needs comprehensive testing

**Requirements:**
- iOS 15.0 or later
- 64-bit device (iPhone 6s and newer)
- Swift 5.9+
- CocoaPods for dependency management

If you encounter iOS-specific issues, please [report them](https://github.com/mbadyl/flutter_leap_sdk/issues) with device/OS details.

## Troubleshooting

### Common Issues

**Model loading fails:**
- Ensure device has sufficient RAM (3GB+ recommended)
- Check model file integrity after download
- Verify device architecture (arm64-v8a for Android)

**Download issues:**
- Check network connectivity
- Ensure sufficient storage space
- Try different model URLs if needed

**iOS-specific issues:**
- Verify iOS version (15.0+)
- Check CocoaPods installation
- Report iOS bugs with device details

### Performance Tips

- Use smaller models (LFM2-350M) for basic tasks
- Monitor memory usage during model operations
- Unload models when not needed to free memory
- Use streaming for better user experience

## Contributing

Contributions are welcome! Areas where help is especially needed:

- 📱 **iOS testing**: Help test on various iOS devices and versions
- 🐛 **Bug reports**: Especially iOS-specific issues
- 📖 **Documentation**: Improve examples and guides
- ✨ **Features**: Function calling, advanced conversation management

Please submit Pull Requests or [file issues](https://github.com/mbadyl/flutter_leap_sdk/issues).

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.

---

**Author**: Mikolaj Badyl (mikolajbady0@gmail.com)  
**Built with**: [Liquid AI LEAP SDK](https://leap.liquid.ai)