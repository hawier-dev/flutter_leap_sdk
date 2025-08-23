# Flutter LEAP SDK

A Flutter plugin for integrating Liquid AI's LEAP SDK, enabling on-device deployment of small language models in Flutter applications.

## Platform Support

| Platform | Status | Notes |
|----------|--------|--------|
| Android  | ✅ Supported | API 31+, arm64-v8a |
| iOS      | 🚧 Partial Support | iOS 14+, SDK placeholder ready |

## Features

- ✅ Model downloading with progress tracking
- ✅ Model loading and management  
- ✅ Text generation (blocking and streaming)
- ✅ Model lifecycle management
- ✅ Built on official Liquid AI LEAP SDK

## Getting Started

### Prerequisites

- Flutter SDK
- **Android**: Device with `arm64-v8a` ABI, minimum API level 31
- **iOS**: Device with iOS 14+, 64-bit architecture (iPhone 6s and newer)
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

// Download a model
await FlutterLeapSdkService.downloadModel(
  modelName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
  onProgress: (progress) => print('Download: ${progress.percentage}%'),
);

// Load the model
await FlutterLeapSdkService.loadModel(
  modelPath: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
);

// Generate response
String response = await FlutterLeapSdkService.generateResponse('Hello, AI!');
print(response);

// Or use streaming
FlutterLeapSdkService.generateResponseStream('Hello, AI!').listen(
  (chunk) => print('Chunk: $chunk'),
);
```

### Available Models

- **LFM2-350M** (322 MB) - Smallest model, good for basic tasks
- **LFM2-700M** (610 MB) - Balanced performance and size  
- **LFM2-1.2B** (924 MB) - Best performance, larger size

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
          modelName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
          onProgress: (progress) {
            print('Download progress: ${progress.percentage}%');
          },
        );
      }

      // Load the model
      await FlutterLeapSdkService.loadModel(
        modelPath: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
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

## API Reference

### FlutterLeapSdkService

#### Model Management
- `loadModel({String? modelPath})` - Load a model from local storage
- `unloadModel()` - Unload the currently loaded model
- `checkModelLoaded()` - Check if a model is currently loaded
- `checkModelExists(String modelName)` - Check if model file exists locally

#### Text Generation  
- `generateResponse(String message)` - Generate complete response
- `generateResponseStream(String message)` - Generate streaming response
- `cancelStreaming()` - Cancel active streaming generation

#### Model Download & Management
- `downloadModel({String? modelUrl, String? modelName, Function(DownloadProgress)? onProgress})` - Download model with progress
- `getDownloadedModels()` - List all downloaded model files
- `deleteModel(String fileName)` - Delete a downloaded model
- `getModelInfo(String fileName)` - Get model information

## Additional Information

This package is built on top of Liquid AI's official LEAP SDK. For more information about LEAP SDK and Liquid AI, visit [leap.liquid.ai](https://leap.liquid.ai).

### iOS Status

The iOS implementation is currently a placeholder architecture waiting for the official iOS LEAP SDK release. The iOS plugin includes:

- ✅ Complete Flutter-iOS bridge implementation
- ✅ Model downloading support (using flutter_downloader)
- ✅ Plugin architecture ready for LEAP SDK integration
- ⏳ Awaiting official iOS LEAP SDK from Liquid AI

When the iOS LEAP SDK becomes available, simply uncomment the native iOS implementation in `ios/Classes/FlutterLeapSdkPlugin.swift` and add the SDK dependency to the podspec.

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Issues

Please file issues on the [GitHub repository](https://github.com/mbadyl/flutter_leap_sdk/issues).

### License

This project is licensed under the MIT License - see the LICENSE file for details.