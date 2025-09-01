# example

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Custom Models

To use a custom model, you need to provide a URL to the model and a name for it.

In the "Custom Model" section of the app, you will find two text fields: "Model URL" and "Model Name".

1.  **Model URL**: Enter the direct download URL for your custom model. The model should be in a format compatible with the Leap SDK (e.g., a `.bundle` file).
2.  **Model Name**: Enter a unique name for your model. This name will be used to save the model on the device and to load it later.

After entering the URL and name, click the "Download Custom Model" button. The app will download the model and save it on the device.

Once the model is downloaded, you can load it by clicking the "Load Custom Model" button. The app will then use this model for inference.

### Example Usage in Code

Here's how you can download and load a custom model programmatically:

```dart
// To download a custom model
await FlutterLeapSdkService.downloadModel(
  modelUrl: 'https://example.com/model.bundle',
  modelName: 'my-custom-model',
);

// To load the custom model
await FlutterLeapSdkService.loadModel(modelPath: 'my-custom-model');
```