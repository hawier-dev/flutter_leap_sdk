/// Base exception class for all Flutter LEAP SDK errors.
///
/// All SDK-specific exceptions extend this class and provide
/// a message and optional error code for debugging.
class FlutterLeapSdkException implements Exception {
  /// Human-readable error message
  final String message;

  /// Optional error code for programmatic handling
  final String? code;

  const FlutterLeapSdkException(this.message, this.code);

  @override
  String toString() => 'FlutterLeapSdkException($code): $message';
}

/// Exception thrown when model loading fails.
///
/// This can occur due to invalid model paths, corrupted files,
/// insufficient memory, or incompatible model formats.
class ModelLoadingException extends FlutterLeapSdkException {
  const ModelLoadingException(super.message, super.code);
}

/// Exception thrown when attempting operations on an unloaded model.
///
/// Indicates that a model must be loaded before performing
/// text generation or other model-dependent operations.
class ModelNotLoadedException extends FlutterLeapSdkException {
  const ModelNotLoadedException()
    : super('Model is not loaded. Call loadModel() first.', 'MODEL_NOT_LOADED');
}

/// Exception thrown when text generation fails.
///
/// Can occur due to model errors, invalid input, memory issues,
/// or interrupted generation processes.
class GenerationException extends FlutterLeapSdkException {
  const GenerationException(super.message, super.code);
}

/// Exception thrown during model download operations.
///
/// Covers network errors, storage issues, invalid URLs,
/// and other download-related failures.
class DownloadException extends FlutterLeapSdkException {
  const DownloadException(super.message, super.code);
}
