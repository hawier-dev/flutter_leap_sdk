class FlutterLeapSdkException implements Exception {
  final String message;
  final String? code;

  const FlutterLeapSdkException(this.message, this.code);

  @override
  String toString() => 'FlutterLeapSdkException($code): $message';
}

class ModelLoadingException extends FlutterLeapSdkException {
  const ModelLoadingException(String message, String? code) : super(message, code);
}

class ModelNotLoadedException extends FlutterLeapSdkException {
  const ModelNotLoadedException() : super('Model is not loaded. Call loadModel() first.', 'MODEL_NOT_LOADED');
}

class GenerationException extends FlutterLeapSdkException {
  const GenerationException(String message, String? code) : super(message, code);
}

class DownloadException extends FlutterLeapSdkException {
  const DownloadException(String message, String? code) : super(message, code);
}